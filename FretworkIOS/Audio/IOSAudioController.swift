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

    // MARK: - AudioControlling

    var onEvent: (@MainActor @Sendable (AudioControllerEvent) -> Void)?

    // MARK: - iOS-only observable surface

    private(set) var status: IOSAudioStatus = .idle
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

    // MARK: - Seams (injected; fakes in the default suite satisfy C-11)

    private let session: IOSAudioSessionControlling
    private let foreground: IOSForegroundObserving
    private let graphBuilder: IOSAudioGraphBuilding
    private let playerFactory: @Sendable (NoteSampleLibrary, Double) -> SamplePlayer
    private let playThroughPlayer: @Sendable (SamplePlayer, Int, Int, Double, Float) -> Void

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
         }) {
        self.session = session
        self.foreground = foreground
        self.graphBuilder = graphBuilder
        self.playerFactory = playerFactory
        self.playThroughPlayer = playThroughPlayer

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
    }

    // MARK: - Foreground policy

    func setForegroundActive(_ active: Bool) {
        foregroundActive = active
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
        let analysisWorker = AudioAnalysisWorker(ring: analysisRing, sensitivity: sensitivity)
        let chordWorker = ChordAnalysisWorker(ring: chordRing)
        analysisWorker.onUpdate = { [weak self] display, _ in
            Task { @MainActor [weak self] in self?.onEvent?(.noteUpdate(display)) }
        }
        chordWorker.onUpdate = { [weak self] chord in
            Task { @MainActor [weak self] in self?.onEvent?(.chordUpdate(chord)) }
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
                    chordRing: chordRing
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
                analysisWorker.start(sampleRate: sampleRate, bufferSize: 1024)
                chordWorker.setEnabled(chordEnabled)
                chordWorker.start(sampleRate: sampleRate)
                self.status = .listening
                if notifyRecovered { self.onEvent?(.recovered) }
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
        let message = String(describing: error)
        status = .failed(message)
        onEvent?(.error(message))
    }

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
        chordRing: RingBuffer
    ) async throws -> IOSAudioGraphHandling {
        let graph = try builder.build(
            leg: leg,
            sessionSampleRate: sampleRate,
            analysisRing: analysisRing,
            chordRing: chordRing
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
