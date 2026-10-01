import AVFoundation
import Foundation
import Observation

/// The production iOS audio controller: one `AVAudioEngine`, an
/// `AVAudioSession`-managed route, and no live-monitoring path (C-03).
///
/// It sits behind the shared `AudioControlling` seam, so `AppState` is unaware
/// it is on iOS. The richer iOS state (`status`, permission, session metrics)
/// lives here and is read by iOS-only surfaces through the `AppState.iosAudio`
/// cast.
///
/// **One engine, not two.** The Mac uses two because input and output are
/// independently selected physical devices with independent clocks. iOS has one
/// system-managed route, one clock and no device selection, so two engines would
/// be two sessions fighting over the same route for no benefit. The capture leg
/// dead-ends into `CaptureSink`; sample playback feeds `mainMixerNode`; there is
/// no edge from input to any output.
///
/// **No realtime block is built here.** `CaptureSink` and `SamplePlayer` create
/// their receiver/render blocks in their own nonisolated `init`s; this type only
/// constructs them off the main actor. A block written in a `@MainActor` context
/// carries an executor check and traps on its first realtime callback
/// (Phase 1, commit `e858416`), so the graph build is deliberately nonisolated
/// (`SystemIOSAudioGraphBuilder`, `buildAndStart`).
///
/// **Ordering.** Every session activation/deactivation and every graph
/// build/start/stop is serialized through `enqueueTransition`, one after the
/// other, so a burst of foreground/background notifications cannot interleave a
/// stop with a start or double-activate the session.
@MainActor @Observable
final class IOSAudioController: AudioControlling {

    /// How long after the last scheduled sample's nominal end the playback
    /// gate keeps suppressing detection. Derived from the detector's own
    /// latency, not from any acoustic tail: both device runs (quiet room,
    /// noise floor -66 dB; TV/talking room, floor -52 dB) showed the mic level
    /// back at its floor within ~0.25–0.5 s of the sample's nominal end and
    /// **zero** detections of the played pitch after the end in the quiet room
    /// — the speaker tail is effectively zero. The margin therefore only has
    /// to cover the note detector's latency: the 2048-sample YIN window must
    /// fully flush (2048 / 48000 ≈ 43 ms at the iPhone's session rate) plus the
    /// worker's 3-of-5 median confirmation (3 publishes at its 33 ms cadence
    /// ≈ 99 ms). 43 ms + 99 ms = 142 ms, rounded up to 150 ms. A longer hold
    /// would only mute the next real note; a shorter one risks re-confirming
    /// the sample's own tail while the window still holds it.
    static let samplePlaybackGateTail: TimeInterval = 0.150

    // MARK: - AudioControlling

    var onEvent: (@MainActor @Sendable (AudioControllerEvent) -> Void)?

    /// RAW (ungated) worker updates, for the DEBUG bleed probe only: fired on
    /// every note/chord worker update regardless of the playback gate, so the
    /// probe can report both gated and ungated detection. Production consumers
    /// must use `onEvent`, which is the gated stream `AppState` sees.
    var onRawWorkerUpdate: (@MainActor @Sendable (AudioControllerEvent) -> Void)?

    // MARK: - iOS-only observable surface

    private(set) var status: IOSAudioStatus = .idle
    /// True while the playback gate is suppressing detection — any app sample
    /// sounding through its nominal end plus `samplePlaybackGateTail`. A stored
    /// flag written **only** on a real `.closed`/`.opened` transition (see
    /// `playbackGate`, which is `@ObservationIgnored`), so readers are never
    /// invalidated at worker cadence. The Listen pill reads it to say
    /// "Playing" instead of "Listening".
    private(set) var isSuppressingForPlayback = false
    /// The current microphone permission, read from the session seam. Exposed
    /// so the Listen screen's start-decision logic can tell `.idle`-after-grant
    /// apart from `.idle`-after-denial without reaching into the session.
    var recordPermission: IOSAudioRecordPermission { session.recordPermission }
    /// True once the bundled 138-note library has been decoded.
    var isSampleLibraryLoaded: Bool { sampleLibrary != nil }
    var isSamplePlaybackReady: Bool { run?.player != nil && (run?.graph.isRunning ?? false) }
    /// The session figures the smoke view writes to stderr so a device run is
    /// readable from `devicectl … --console`.
    var sessionSampleRate: Double { session.sampleRate }
    /// The system route's input channel count. The sink receives the mono
    /// downmix; this is the hardware figure a device run logs to check the
    /// mono boundary (design check D-7).
    var sessionInputChannelCount: Int { session.inputChannelCount }
    var sessionInputLatency: TimeInterval { session.inputLatency }
    var sessionIOBufferDuration: TimeInterval { session.ioBufferDuration }
    /// The rate the capture sink actually delivers — the engine input node's
    /// format rate once the graph is up. This is what the pitch/chord workers
    /// are told; a session log that disagrees with `sessionSampleRate` is the
    /// smoking gun for a frequency-scale error.
    var captureSampleRate: Double? { run?.graph.captureSampleRate }

    // MARK: - Seams (injected; fakes in the default suite satisfy C-11)

    private let session: IOSAudioSessionControlling
    private let foreground: IOSForegroundObserving
    private let graphBuilder: IOSAudioGraphBuilding
    private let playerFactory: @Sendable (NoteSampleLibrary, Double) -> SamplePlayer
    private let playThroughPlayer: @Sendable (SamplePlayer, Int, Int, Double, Float) -> Void
    /// Monotonic time source for the playback gate. Injectable so gate timing
    /// can be stepped deterministically in tests.
    private let now: @Sendable () -> TimeInterval

    // MARK: - State

    private var foregroundActive = false
    private var userWantsListening = false
    /// Whether the session is currently activated, so teardown never appends a
    /// spurious `setActive(false)` for a session that was never opened.
    private var sessionActive = false
    /// Set once a note has been asked for outside a listening run; keeps an
    /// `.outputOnly` run alive so a module can play examples without the mic.
    private var wantsPlaybackGraph = false
    private(set) var sampleLibrary: NoteSampleLibrary?
    private var run: IOSAudioRun?
    private var generation = 0
    private var chordDetectionEnabled = false
    private let sensitivity = SensitivitySettings()
    private let libraryQueue = DispatchQueue(label: "com.fretwork.ios.sample-library", qos: .userInitiated)
    private var transitionTask: Task<Void, Never>?
    /// Incremented on every enqueue so `settleGraphWork()` can await the chain
    /// to quiescence rather than a single link (a transition may enqueue the
    /// next one, e.g. permission grant → run build).
    private var transitionSerial = 0
    /// The playback gate: suppresses note/chord events while any app sample
    /// is sounding (through its nominal end) plus `samplePlaybackGateTail`.
    /// `@ObservationIgnored` because it is mutated at worker cadence; the
    /// observable surface is `isSuppressingForPlayback`, written only on a
    /// real transition.
    @ObservationIgnored
    private var playbackGate: PlaybackGate
    /// A wake-up scheduled to `gateEnd`, so the `.opened` transition (and the
    /// `isSuppressingForPlayback` flip) happens even with no worker traffic.
    /// Cancelled and re-armed on every play that extends the window, and on
    /// teardown.
    @ObservationIgnored
    private var gateLiftTask: Task<Void, Never>?
    #if DEBUG
    /// The `-FretworkCaptureDump` writer and its 60 s flush timer. Only ever
    /// non-nil in DEBUG when the launch argument is present.
    @ObservationIgnored
    private var captureDumpWriter: CaptureDumpWriter?
    @ObservationIgnored
    private var captureDumpFlushTask: Task<Void, Never>?
    #endif

    private struct IOSAudioRun {
        let leg: IOSAudioGraphLeg
        let analysisWorker: AudioAnalysisWorker
        let chordWorker: ChordAnalysisWorker
        let graph: IOSAudioGraphHandling
        var player: SamplePlayer?
    }

    // MARK: - Init

    init(session: IOSAudioSessionControlling = SystemIOSAudioSession(),
         foreground: IOSForegroundObserving = SystemIOSForegroundObserver(),
         graphBuilder: IOSAudioGraphBuilding = SystemIOSAudioGraphBuilder(),
         playerFactory: @escaping @Sendable (NoteSampleLibrary, Double) -> SamplePlayer = { library, sampleRate in
             // Mono, same as the graph leg; a 48 kHz fallback is always valid,
             // so the force unwrap cannot fire.
             let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
                 ?? AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
             return SamplePlayer(library: library, format: format)
         },
         playThroughPlayer: @escaping @Sendable (SamplePlayer, Int, Int, Double, Float) -> Void = { player, string, fret, rate, gain in
             player.play(string: string, fret: fret, rateMultiplier: rate, gain: gain)
         },
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.session = session
        self.foreground = foreground
        self.graphBuilder = graphBuilder
        self.playerFactory = playerFactory
        self.playThroughPlayer = playThroughPlayer
        self.now = now
        self.playbackGate = PlaybackGate(tail: Self.samplePlaybackGateTail)

        foreground.onForegroundChange = { [weak self] active in
            self?.setForegroundActive(active)
        }
        session.onInterruption = { [weak self] interruption in
            self?.handleInterruption(interruption)
        }
        session.onRouteChange = { [weak self] reason in
            self?.handleRouteChange(reason)
        }
        session.onMediaServicesReset = { [weak self] in
            self?.handleMediaServicesReset()
        }
    }

    isolated deinit {
        run?.analysisWorker.stop()
        run?.chordWorker.stop()
        run?.graph.stop()
    }

    // MARK: - AudioControlling lifecycle

    @discardableResult
    func start() -> Bool {
        switch session.recordPermission {
        case .denied:
            handlePermissionDenied()
            return false
        case .granted:
            userWantsListening = true
            updateAudioNeed()
            return true
        case .undetermined:
            userWantsListening = true
            status = .starting
            let gen = generation
            enqueueTransition { [weak self] in
                guard let self, gen == self.generation else { return }
                let granted = await self.session.requestRecordPermission()
                // Stop/background during the system prompt must not later
                // activate audio: the generation guard is the Phase 1
                // mitigation, re-implemented rather than inherited.
                guard gen == self.generation, self.userWantsListening else { return }
                if granted {
                    self.updateAudioNeed()
                } else {
                    self.handlePermissionDenied()
                }
            }
            return true
        }
    }

    func stop() {
        userWantsListening = false
        wantsPlaybackGraph = false
        generation &+= 1
        status = .idle
        teardownRun(deactivate: true)
    }

    func setChordDetectionEnabled(_ enabled: Bool) {
        // Only flips the worker flag; never rebuilds the graph, matching the
        // seam's contract and the Mac `AppShellNavigationTests` rule.
        chordDetectionEnabled = enabled
        run?.chordWorker.setEnabled(enabled)
    }

    func setSensitivity(_ value: Double) {
        sensitivity.value = value
    }

    // MARK: - Sample playback

    func prepareSamplePlayback(completion: (@Sendable (String?) -> Void)?) {
        if let library = sampleLibrary {
            attachPlayerIfNeeded(library: library)
            completion?(nil)
            return
        }
        libraryQueue.async { [weak self] in
            do {
                let library = try NoteSampleLibrary.loadFromBundle()
                // A `Task { @MainActor in … }` rather than `await
                // MainActor.run` inside this non-async closure: the closure is
                // `@Sendable () -> Void`, so it cannot await at all.
                Task { @MainActor [weak self] in
                    guard let self else {
                        completion?(nil)
                        return
                    }
                    self.sampleLibrary = library
                    self.attachPlayerIfNeeded(library: library)
                    // Eagerly open the output-only graph so playback readiness
                    // becomes true without a play attempt. Otherwise the first
                    // `playSample` is a silent no-op while the async build
                    // lands — the "silently mute" gotcha, mirrored from the
                    // Mac's rebuild-to-attach.
                    if self.run == nil, self.foregroundActive, !self.userWantsListening {
                        self.wantsPlaybackGraph = true
                        self.updateAudioNeed()
                    }
                    completion?(nil)
                }
            } catch {
                let message = String(describing: error)
                Task { @MainActor in completion?(message) }
            }
        }
    }

    func playSample(string: Int, fret: Int, tuning: Tuning) {
        guard let resolution = TuningSampleMap.resolve(tuning: tuning, string: string, fret: fret) else { return }
        if run == nil {
            // No listening session: an output-only run needs no microphone
            // permission and opens no mic.
            wantsPlaybackGraph = true
            updateAudioNeed()
        }
        guard let player = run?.player else { return }
        playThroughPlayer(player, string, resolution.fret, resolution.rateMultiplier, 1)
        // Playback gate: suppress detection from this play call until the
        // played take's nominal end (overlapping plays extend it). The take is
        // looked up by its *source* fret — `resolution.fret` — because that is
        // the audio the player is about to read.
        if let sample = sampleLibrary?.sample(string: string, fret: resolution.fret) {
            let duration = Double(sample.frameCount) / sample.sampleRate / resolution.rateMultiplier
            let transition = playbackGate.recordPlay(duration: duration, at: now())
            if transition == .closed {
                if !isSuppressingForPlayback { isSuppressingForPlayback = true }
                // The gate just closed: clear the readout so a note detected
                // before playback does not linger on screen while the app is
                // audibly playing its own sample.
                onEvent?(.noteUpdate(PitchDisplayState()))
                onEvent?(.chordUpdate(ChordDisplayState()))
            }
            scheduleGateLiftCheck()
        }
    }

    // MARK: - Foreground policy

    func setForegroundActive(_ active: Bool) {
        foregroundActive = active
        #if DEBUG
        if !active { flushCaptureDump() }
        #endif
        updateAudioNeed()
    }

    private func updateAudioNeed() {
        guard foregroundActive else {
            if run != nil { teardownRun(deactivate: true) }
            if status != .interrupted { status = .idle }
            return
        }
        if userWantsListening {
            if run?.leg != .captureAndOutput {
                scheduleRun(leg: .captureAndOutput, notifyRecovered: false)
            }
        } else if wantsPlaybackGraph, sampleLibrary != nil {
            if run?.leg != .outputOnly {
                scheduleRun(leg: .outputOnly, notifyRecovered: false)
            }
        } else {
            if run != nil { teardownRun(deactivate: true) }
            if status != .interrupted { status = .idle }
        }
    }

    // MARK: - Interruption / reset

    private func handleInterruption(_ interruption: IOSAudioInterruption) {
        switch interruption.kind {
        case .began:
            status = .interrupted
            onEvent?(.reconnecting)
            teardownRun(deactivate: false)
        case .ended:
            guard interruption.shouldResume, userWantsListening, foregroundActive else {
                status = .idle
                return
            }
            scheduleRun(leg: .captureAndOutput, notifyRecovered: true)
        }
    }

    private func handleRouteChange(_ reason: IOSAudioRouteChangeReason) {
        // Route changes are deliberately transparent for Phase 3 (see the
        // design's D-4 risk): the session keeps the engine on the new system
        // route, and only a proven failure justifies the debounced rebuild that
        // Phase 3 does not yet stress-test. Recorded so the smoke view can show
        // it on device.
        lastRouteChange = reason
    }

    private(set) var lastRouteChange: IOSAudioRouteChangeReason?

    private func handleMediaServicesReset() {
        let message = "The audio system was reset. Reconnecting…"
        status = .failed(message)
        onEvent?(.error(message))
        teardownRun(deactivate: false)
        if userWantsListening, foregroundActive {
            scheduleRun(leg: .captureAndOutput, notifyRecovered: true)
        }
    }

    private func handlePermissionDenied() {
        userWantsListening = false
        wantsPlaybackGraph = false
        teardownRun(deactivate: true)
        status = .permissionDenied
        onEvent?(.error("Microphone permission is off. Enable it in Settings."))
    }

    // MARK: - Run lifecycle (all graph work serialized off the main actor)

    private func scheduleRun(leg: IOSAudioGraphLeg, notifyRecovered: Bool) {
        generation &+= 1
        let gen = generation
        // Only a capture run is "starting"/"listening". A playback-only run
        // (samples loaded, mic never opened) must leave the status alone, or the
        // UI claims to be listening while no input exists.
        let captures = leg == .captureAndOutput
        if captures { status = .starting }

        // Replace any current run here, synchronously, instead of capturing it
        // in the transition closure below. A closure chained behind previous
        // transitions stays alive until the chain unwinds, so capturing the old
        // run kept every stopped engine (and its rings/workers) alive across
        // fg/bg cycles.
        let existingPlayer = run?.player
        if let oldRun = run {
            run = nil
            stopRunNow(oldRun)
        }

        let analysisRing = RingBuffer(capacity: 65_536)
        let chordRing = RingBuffer(capacity: 65_536)
        #if DEBUG
        // -FretworkCaptureDump: give the dump its own ring fed by the same
        // CaptureSink (never a second reader on an existing ring).
        let dumpEnabled = CommandLine.arguments.contains("-FretworkCaptureDump")
        let recordingRing = dumpEnabled ? RingBuffer(capacity: 65_536) : nil
        #else
        let recordingRing: RingBuffer? = nil
        #endif
        let analysisWorker = AudioAnalysisWorker(ring: analysisRing, sensitivity: sensitivity)
        let chordWorker = ChordAnalysisWorker(ring: chordRing)
        analysisWorker.onUpdate = { [weak self] display, _ in
            Task { @MainActor [weak self] in self?.forwardNoteUpdate(display) }
        }
        chordWorker.onUpdate = { [weak self] chord in
            Task { @MainActor [weak self] in self?.forwardChordUpdate(chord) }
        }

        let sampleRate = session.sampleRate
        let builder = graphBuilder
        let chordEnabled = chordDetectionEnabled

        enqueueTransition { [weak self] in
            guard let self, gen == self.generation else { return }

            do {
                try self.activateSession(for: leg)
                let graph = try await Self.buildAndStart(
                    builder: builder,
                    leg: leg,
                    sampleRate: sampleRate,
                    analysisRing: analysisRing,
                    chordRing: chordRing,
                    recordingRing: recordingRing
                )
                // A newer transition superseded this build while it was off the
                // main actor; discard the dead engine instead of leaking it.
                guard gen == self.generation else {
                    await Self.stopGraph(graph)
                    return
                }

                var newRun = IOSAudioRun(
                    leg: leg,
                    analysisWorker: analysisWorker,
                    chordWorker: chordWorker,
                    graph: graph,
                    player: existingPlayer
                )
                if let library = self.sampleLibrary {
                    let player = existingPlayer ?? self.playerFactory(library, graph.sampleRate)
                    graph.attachPlayer(player)
                    newRun.player = player
                }
                self.run = newRun
                // Nothing feeds the rings without the input leg, so detection
                // workers would only poll empty buffers.
                guard captures else { return }
                // The workers must be told the rate of the samples in their
                // rings — the input node's format rate, not the session rate
                // captured above (which is read before activation and can
                // disagree with what the sink actually delivers). A mismatch
                // here scales every detected frequency by the ratio, which is
                // exactly the class of error that read low notes flat on iOS
                // while the Mac (which passes the tap's format rate) stayed
                // correct.
                let workerRate = graph.captureSampleRate ?? sampleRate
                analysisWorker.start(sampleRate: workerRate, bufferSize: 1024)
                chordWorker.setEnabled(chordEnabled)
                chordWorker.start(sampleRate: workerRate)
                self.status = .listening
                if notifyRecovered { self.onEvent?(.recovered) }
                #if DEBUG
                if let recordingRing {
                    let writer = CaptureDumpWriter(ring: recordingRing)
                    self.captureDumpWriter = writer
                    writer.start()
                    self.captureDumpFlushTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(60))
                        self?.flushCaptureDump()
                    }
                    FileHandle.standardError.write(Data("capture-dump recording\n".utf8))
                }
                #endif
            } catch {
                if self.sessionActive {
                    try? self.session.setActive(false)
                    self.sessionActive = false
                }
                self.fail(error)
            }
        }
    }

    private func teardownRun(deactivate: Bool) {
        // Invalidate any in-flight build so it cannot adopt a run after us.
        generation &+= 1
        // No run means no more playback: drop any pending lift wake-up and
        // leave the flag for the next run's worker traffic to re-evaluate
        // (the pill only shows "Playing" while `.listening`, so a stale true
        // here is invisible).
        gateLiftTask?.cancel()
        gateLiftTask = nil
        if let oldRun = run {
            run = nil
            stopRunNow(oldRun)
        }
        if deactivate, sessionActive {
            try? session.setActive(false)
            sessionActive = false
        }
    }

    /// Stops a run's workers and engine on the main actor. Stopping is cheap
    /// and, crucially, doing it here means the run is released immediately
    /// rather than being retained by a queued transition closure.
    private func stopRunNow(_ run: IOSAudioRun) {
        run.analysisWorker.stop()
        run.chordWorker.stop()
        run.graph.stop()
    }

    private func activateSession(for leg: IOSAudioGraphLeg) throws {
        switch leg {
        case .captureAndOutput:
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        case .outputOnly:
            // Playback-only never touches `engine.inputNode`, so it needs no
            // microphone permission.
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try session.setActive(true)
        sessionActive = true
    }

    private func attachPlayerIfNeeded(library: NoteSampleLibrary) {
        guard let run, run.player == nil else { return }
        let player = playerFactory(library, run.graph.sampleRate)
        self.run?.player = player
        run.graph.attachPlayer(player)
    }

    private func fail(_ error: Error) {
        // `setActive` on a session another app is holding throws
        // AVAudioSessionErrorCodeInsufficientPriority (561017449). Surface it
        // as an actionable message with the existing Retry rather than a raw
        // code, which the player cannot act on.
        let message: String
        if (error as NSError).code == AVAudioSession.ErrorCode.insufficientPriority.rawValue {
            message = "Audio is in use by another app. Close it, then try again."
        } else {
            message = String(describing: error)
        }
        status = .failed(message)
        onEvent?(.error(message))
    }

    // MARK: - Playback gate forwarding

    /// Drops the triggering pre-gate update plus the one already in flight on
    /// each worker thread when the gate lifts, so a reading computed before the
    /// reset can never leak out. Two per stream covers the worst realistic
    /// case: the update being processed (the one that saw the gate open) and
    /// the one the worker computed before observing the reset flag.
    private var dropNextNote = 0
    private var dropNextChord = 0

    /// The gated path every worker update takes. The raw value is forwarded to
    /// `onRawWorkerUpdate` first (probe-only), then the playback gate decides
    /// whether `onEvent` — and therefore `AppState` and every consumer — sees
    /// it.
    private func forwardNoteUpdate(_ display: PitchDisplayState) {
        onRawWorkerUpdate?(.noteUpdate(display))
        guard !applyGate() else { return }
        if dropNextNote > 0 {
            dropNextNote -= 1
            return
        }
        onEvent?(.noteUpdate(display))
    }

    private func forwardChordUpdate(_ chord: ChordDisplayState) {
        onRawWorkerUpdate?(.chordUpdate(chord))
        guard !applyGate() else { return }
        if dropNextChord > 0 {
            dropNextChord -= 1
            return
        }
        onEvent?(.chordUpdate(chord))
    }

    /// Recomputes the gate at the current time and returns true while
    /// suppression is active. On the closed→open transition the workers are
    /// reset, so a reading computed from pre-gate audio cannot leak into the
    /// first post-gate update; the stale in-flight updates are then dropped by
    /// the counters above.
    private func applyGate() -> Bool {
        switch playbackGate.update(at: now()) {
        case .opened:
            setGateOpen()
        case .closed, .none:
            break
        }
        return playbackGate.isSuppressed
    }

    /// The closed→open transition, however it is observed (a worker update
    /// calling `applyGate`, or the scheduled lift check firing at `gateEnd`):
    /// publish the flag flip once, then reset the workers and drop the stale
    /// in-flight frames so nothing computed before the reset leaks out.
    private func setGateOpen() {
        if isSuppressingForPlayback { isSuppressingForPlayback = false }
        run?.analysisWorker.reset()
        run?.chordWorker.reset()
        dropNextNote = 2
        dropNextChord = 2
    }

    /// Arms (or re-arms, cancelling the previous) a main-actor task that fires
    /// exactly at `gateEnd`. This is what makes the lift transition happen on
    /// time even when no worker update arrives around it — the flag is not
    /// observable time and `gateEnd` is never cleared, so the transition must
    /// be driven, not read.
    private func scheduleGateLiftCheck() {
        gateLiftTask?.cancel()
        guard let end = playbackGate.gateEnd else { return }
        let delay = end - now()
        guard delay > 0 else { return }
        gateLiftTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            switch self.playbackGate.update(at: self.now()) {
            case .opened:
                self.setGateOpen()
            case .closed, .none:
                break
            }
        }
    }

    #if DEBUG
    /// Writes the raw capture dump (the last ≤20 s at the real capture rate)
    /// to a Float32 WAV in Documents and logs its path. Idempotent; fired on
    /// background or after 60 s, whichever comes first.
    private func flushCaptureDump() {
        guard let writer = captureDumpWriter else { return }
        captureDumpWriter = nil
        captureDumpFlushTask?.cancel()
        captureDumpFlushTask = nil

        let frames = writer.stopAndTake()
        let rate = run?.graph.captureSampleRate ?? 48_000
        let keepFrames = min(frames.count, Int(rate) * 20)
        let trimmed = frames.suffix(keepFrames)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent(
            "fretwork-capture-\(Int(Date().timeIntervalSince1970)).wav")
        do {
            try CaptureDumpWriter.writeWAV(Array(trimmed), sampleRate: rate, to: url)
            FileHandle.standardError.write(Data("capture-dump path=\(url.path) frames=\(trimmed.count) rate=\(Int(rate))\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("capture-dump error=\(error)\n".utf8))
        }
    }
    #endif

    // MARK: - Transitions

    /// Chains one unit of graph/session work behind the previous one. The work
    /// itself is `@MainActor`, but the slow parts it `await`s are nonisolated,
    /// so `engine.start()`/`inputNode`/`setActive` never block the main thread.
    private func enqueueTransition(_ work: @escaping @MainActor () async -> Void) {
        transitionSerial &+= 1
        let serial = transitionSerial
        let previous = transitionTask
        transitionTask = Task { @MainActor [weak self] in
            await previous?.value
            await work()
            // Release the completed link (and whatever its closure captured)
            // as soon as it is no longer the newest transition. Without this
            // the serialized chain retained every completed closure — and the
            // stopped engines they had built — until the next enqueue.
            if let self, self.transitionSerial == serial {
                self.transitionTask = nil
            }
        }
    }

    /// Awaits every queued transition, including ones enqueued while awaiting.
    /// For tests only — production never needs to know when the graph settled.
    func settleGraphWork() async {
        var seen = -1
        while seen != transitionSerial {
            seen = transitionSerial
            await transitionTask?.value
        }
    }

    // MARK: - Nonisolated graph work

    private nonisolated static func buildAndStart(
        builder: IOSAudioGraphBuilding,
        leg: IOSAudioGraphLeg,
        sampleRate: Double,
        analysisRing: RingBuffer,
        chordRing: RingBuffer,
        recordingRing: RingBuffer?
    ) async throws -> IOSAudioGraphHandling {
        let graph = try builder.build(
            leg: leg,
            sessionSampleRate: sampleRate,
            analysisRing: analysisRing,
            chordRing: chordRing,
            recordingRing: recordingRing
        )
        do {
            try graph.start()
        } catch {
            graph.stop()
            throw error
        }
        return graph
    }

    private nonisolated static func stopGraph(_ graph: IOSAudioGraphHandling) async {
        graph.stop()
    }

    // MARK: - Test hooks

    /// The decoded note library, so the DEBUG-only bleed probe can compute a
    /// take's nominal duration and peak straight from the library the player
    /// is about to read, instead of decoding a second 85 MB copy.
    var sampleLibraryForTesting: NoteSampleLibrary? { sampleLibrary }

    var currentAnalysisWorkerForTesting: AudioAnalysisWorker? { run?.analysisWorker }
    var currentChordWorkerForTesting: ChordAnalysisWorker? { run?.chordWorker }
    var currentGraphForTesting: IOSAudioGraphHandling? { run?.graph }
    var currentLeg: IOSAudioGraphLeg? { run?.leg }
    var hasRunForTesting: Bool { run != nil }
    var sensitivityValueForTesting: Double { sensitivity.value }

    /// Drives one synthetic worker update through the gate exactly as a real
    /// worker `onUpdate` would, so tests can prove suppression/delivery and the
    /// reset-on-lift drop without standing up a live ring buffer. Returns true
    /// when the update reached `onEvent`.
    @discardableResult
    func deliverWorkerNoteForTesting(_ display: PitchDisplayState) -> Bool {
        let delivered = !playbackGate.isSuppressed && dropNextNote == 0
        forwardNoteUpdate(display)
        return delivered
    }

    /// Same as `deliverWorkerNoteForTesting` for the chord stream.
    @discardableResult
    func deliverWorkerChordForTesting(_ chord: ChordDisplayState) -> Bool {
        let delivered = !playbackGate.isSuppressed && dropNextChord == 0
        forwardChordUpdate(chord)
        return delivered
    }

    /// Whether the playback gate is currently suppressing the gated stream.
    var isPlaybackGateSuppressedForTesting: Bool { playbackGate.isSuppressed }

    /// A stable category/mode label for the smoke log, derived from the active
    /// leg rather than asking `AVAudioSession` after the fact.
    var sessionConfigurationDescription: String {
        switch currentLeg {
        case .captureAndOutput: "playAndRecord/measurement"
        case .outputOnly: "playback/default"
        case nil: "inactive"
        }
    }
}
