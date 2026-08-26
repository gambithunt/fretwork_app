import AVFoundation
import AudioToolbox
import Foundation
import Darwin

/// Captures from `inputDeviceID` and monitors out to `outputDeviceID`.
///
/// There are two graph shapes, and which one is used decides how much delay a
/// player hears between striking a string and hearing it:
///
/// **Duplex (preferred).** When one device serves both directions — any real
/// interface exposes its input and output under a single `AudioDeviceID` — a
/// single `AVAudioEngine` binds its one AUHAL to that device and the input node
/// is wired straight into the main mixer. Capture and playback then happen in
/// the *same* IO cycle off the *same* clock, so monitoring costs one hardware
/// buffer each way and nothing else. This is what a DAW's zero-latency
/// monitoring does, and it is the only way to get into single-digit
/// milliseconds.
///
/// **Split (fallback).** When input and output are genuinely different devices
/// (built-in mic to built-in speakers, say — macOS gives those separate IDs),
/// one AUHAL cannot serve both: `kAudioOutputUnitProperty_CurrentDevice` binds
/// the whole unit to one device, so pointing it at an input device and then a
/// different output device makes the second call fail ("Could not select the
/// output device."). Two engines each get their own AUHAL. Audio then has to
/// cross from one clock domain to the other through a ring buffer and an
/// `AVAudioPlayerNode`, which costs real latency and needs drift correction.
///
/// The split path pulls its monitor audio from an `AVAudioSourceNode` render
/// callback. An earlier attempt at that was abandoned after it hit
/// `kAudioUnitErr_InvalidElement` (-10877) on some interfaces, and it was
/// replaced by a thread that polled the ring and pushed buffers into an
/// `AVAudioPlayerNode`. That diagnosis looks to have been wrong: the same
/// -10877 was later traced to the polling loop busy-spinning hard enough to
/// starve Core Audio's real-time thread, "regardless of which physical device
/// was selected". With the spin gone, pulling works — and pulling is what
/// removes the queue that the pushing design needed.
final class AudioEngine: @unchecked Sendable {
    /// Requested hardware IO buffer, in frames. At 44.1kHz this is 5.8ms per
    /// direction against the 11.6ms a stock 512-frame buffer costs. Clamped
    /// per-device to what the hardware advertises, and skipped entirely if the
    /// driver refuses.
    ///
    /// This is only safe because every stage that touches audio is now a
    /// render callback. While the split path fed a player node from a thread
    /// polling on a 2ms sleep, shrinking the hardware buffer starved that
    /// queue into audible gaps — the buffer size was not an independent knob
    /// when something upstream polled at a fixed rate. 128 frames was tried
    /// and was too aggressive on USB; lower it only against a device that
    /// proves it can hold up.
    private static let targetBufferFrames: UInt32 = 256

    /// Fixed makeup gain applied to the monitor signal only (never the
    /// analysis/chord taps, so detection thresholds are untouched). Exists
    /// because `AVAudioMixerNode.outputVolume` — what the monitor slider
    /// drives — is hard-clamped to 0...1, i.e. unity gain at most: there is
    /// no headroom above it for the slider to reach no matter how it's
    /// mapped. GarageBand's channel strip applies its own preamp/fader gain
    /// on top of that ceiling, which is what makes the same interface sound
    /// louder there than through this app's monitor path even at max.
    /// +4dB (~1.6x amplitude) is a conservative starting point chosen to
    /// close most of that gap without a limiter in the graph to catch a
    /// clipped transient — raise it only after measuring against real
    /// hardware, the same way `targetBufferFrames` was tuned.
    private static let monitorMakeupGainDB: Float = 4

    /// - Parameter volume: the monitor slider, 0...1. Folded into the same
    ///   `globalGain` as the fixed makeup gain — see `monitorGainDB`.
    private static func makeMonitorGainStage(volume: Float) -> AVAudioUnitEQ {
        let stage = AVAudioUnitEQ(numberOfBands: 1)
        // The single band exists only because AVAudioUnitEQ needs at least
        // one; bypassing it leaves `globalGain` as the only thing this node
        // does — a plain gain stage, not a filter.
        stage.bands[0].bypass = true
        stage.globalGain = monitorGainDB(forVolume: volume)
        return stage
    }

    /// Silence, expressed as a `globalGain`. `AVAudioUnitEQ` clamps
    /// `globalGain` to -96 dB, so this is as far down as the stage goes.
    private static let monitorSilenceGainDB: Float = -96

    /// Applies the monitor slider to the monitor leg's own makeup-gain stage,
    /// rather than to the shared mixer's output.
    ///
    /// The slider used to drive `mainMixerNode.outputVolume` directly, which
    /// worked only while monitoring was that mixer's single input. Sample
    /// playback is a second input to the same mixer and must not be governed
    /// by the monitor slider — nor silenced by monitor mute — so the level has
    /// to move off the shared output and onto the leg it belongs to.
    ///
    /// Two other placements were tried first and both are worse:
    ///
    /// - **A dedicated `AVAudioMixerNode` on the leg**, carrying the slider on
    ///   its `outputVolume`. Measured: idle CPU went from a steady ~13% to
    ///   ~30%, same machine, same devices, same occlusion state. An
    ///   `AVAudioMixerNode` is a full converting mixer rather than a fader, and
    ///   on a multi-channel interface (the GP-200 presents six input channels)
    ///   putting two in series makes the graph do that conversion twice.
    /// - **`AVAudioMixing.volume` on the leg's last node**, which is the
    ///   per-input-bus level on the destination mixer and would have been free.
    ///   `AVAudioUnitEQ` does not conform to `AVAudioMixing` — only source-type
    ///   nodes do (`AVAudioSourceNode`, `AVAudioPlayerNode`, `AVAudioInputNode`,
    ///   `AVAudioMixerNode`); effects do not. Because the level was applied
    ///   through a conditional cast, this failed *silently*: it compiled, it
    ///   ran, and the slider simply stopped doing anything. `MonitorLevelTests`
    ///   exists to make that failure loud.
    ///
    /// So the slider multiplies into the gain stage that is already there. The
    /// mapping is the same product as before — slider amplitude times the fixed
    /// makeup gain — just expressed in dB because that is the knob this node
    /// has.
    ///
    /// **Mute is -96 dB, not true zero.** Against a monitor signal peaking
    /// around -6 dBFS that leaves roughly -98 dBFS, which is below the analog
    /// noise floor of any interface this runs through and inaudible at any sane
    /// monitor gain — but it is attenuation, not a disconnect, and worth
    /// knowing when reading a meter rather than listening.
    private static func monitorGainDB(forVolume volume: Float) -> Float {
        guard volume > 0 else { return monitorSilenceGainDB }
        return max(monitorSilenceGainDB, monitorMakeupGainDB + 20 * log10(volume))
    }

    /// The mapping above is the whole of Phase 1's behaviour change, so it is
    /// tested directly rather than only through a rendered graph.
    static func monitorGainDBForTesting(_ volume: Float) -> Float { monitorGainDB(forVolume: volume) }

    private let controlQueue = DispatchQueue(label: "com.fretlight.audio-control", qos: .userInitiated)
    private var captureEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var monitorRenderer: MonitorRenderer?
    private var captureSink: CaptureSink?
    /// The monitor leg's gain stage, carrying both the fixed makeup gain and
    /// the slider. Never the shared mixer's output. See `monitorGainDB`.
    private var monitorLevel: AVAudioUnitEQ?
    private let analysisRing = RingBuffer()
    private let monitorRing = RingBuffer()
    private let chordRing = RingBuffer()
#if DEBUG
    private let recordingRing = RingBuffer()

    /// Drives the sample-capture screen. Idle — not draining at all — until
    /// `setSampleRecordingEnabled(true)`, so it costs nothing in normal use.
    private(set) lazy var sampleRecorder = SampleRecorder(ring: recordingRing)
    private var sampleRecordingEnabled = false
    /// The hardware rate the graph is currently running at, so the recorder
    /// can be started later without re-deriving it from the node.
    private var currentSampleRate: Double = 0
#endif

    /// Nil in Release, where the whole recording stack is compiled out. Kept
    /// as one accessor so the two graph-building paths stay identical between
    /// configurations rather than sprouting conditionals of their own.
    private var recordingRingIfAvailable: RingBuffer? {
#if DEBUG
        recordingRing
#else
        nil
#endif
    }
    private let sensitivity = SensitivitySettings()
    private var worker: AudioAnalysisWorker?
    private var chordWorker: ChordAnalysisWorker?
    /// Persists across a device-change restart, which tears the worker down
    /// and rebuilds it — this is what tells the new one whether it should
    /// pick back up where the toggle left it.
    private var chordDetectionEnabled = false
    var onUpdate: (@Sendable (PitchDisplayState) -> Void)?
    var onChordUpdate: (@Sendable (ChordDisplayState) -> Void)?
    var onError: (@Sendable (String) -> Void)?
    var onRecovered: (@Sendable () -> Void)?
    /// Fired at the start of every automatic recovery attempt — before it's
    /// known to succeed or fail — so the UI can show something during the
    /// retry window instead of sitting silent until either `onRecovered` or
    /// (after the circuit breaker trips) `onError`.
    var onReconnecting: (@Sendable () -> Void)?
    private var timebase = mach_timebase_info_data_t()
    private var configChangeObservers: [NSObjectProtocol] = []
    private var currentInputDeviceID: AudioDeviceID?
    private var currentOutputDeviceID: AudioDeviceID?
    private var currentMonitorVolume: Float = 0
    private var pendingRestart: DispatchWorkItem?
    private var restartAttempts = 0
    private var restartWindowStart = Date.distantPast
    private var didReportConnectionFailure = false
    /// Configuration-change notifications arriving before this instant are our
    /// own doing and must be ignored — see `startSynchronously`.
    private var settledAfter = Date.distantPast

    init() { mach_timebase_info(&timebase) }

    /// Device negotiation can block inside Core Audio; never perform it on the main actor.
    func start(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID, monitorVolume: Float) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            // This is an explicit user action, so it should always clear the
            // previous recovery circuit breaker — even when the same device is
            // selected again via the Retry button.
            self.restartAttempts = 0
            self.restartWindowStart = .distantPast
            self.didReportConnectionFailure = false
            do { try self.startSynchronously(inputDeviceID: inputDeviceID, outputDeviceID: outputDeviceID, monitorVolume: monitorVolume) }
            catch { self.onError?(error.localizedDescription) }
        }
    }

    private func startSynchronously(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID, monitorVolume: Float) throws {
        // A genuinely new device selection (as opposed to our own recovery
        // logic retrying the same pair) gets a clean slate on the circuit
        // breaker below — it's a deliberate action, not another symptom of
        // whatever the previous device was struggling with.
        if inputDeviceID != currentInputDeviceID || outputDeviceID != currentOutputDeviceID {
            restartAttempts = 0
            restartWindowStart = .distantPast
        }
        // Everything from here until the graph is running generates device
        // churn of our own making — tearing the old engines down, and the IO
        // restart that changing the buffer size below forces. Core Audio
        // reports all of it as a configuration change, and the recovery path
        // would treat it as a device misbehaving and rebuild, generating the
        // same churn again: a self-sustaining restart loop. (It is genuinely
        // self-sustaining, not merely repeated: closing the last engine on a
        // device reverts its buffer size, so the next build sets it again.)
        settledAfter = Date().addingTimeInterval(1.5)
        stopSynchronously()
        currentInputDeviceID = inputDeviceID
        currentOutputDeviceID = outputDeviceID
        currentMonitorVolume = monitorVolume

        // Before any engine binds: changing this restarts IO for every client
        // attached to the device, so it must not happen underneath a running
        // graph of ours.
        AudioDeviceEnumerator.setBufferFrameSize(Self.targetBufferFrames, on: inputDeviceID)
        if outputDeviceID != inputDeviceID {
            AudioDeviceEnumerator.setBufferFrameSize(Self.targetBufferFrames, on: outputDeviceID)
        }

        if inputDeviceID == outputDeviceID, AudioDeviceEnumerator.isDuplexCapable(inputDeviceID) {
            try startDuplex(deviceID: inputDeviceID, monitorVolume: monitorVolume)
        } else {
            try startSplit(inputDeviceID: inputDeviceID, outputDeviceID: outputDeviceID, monitorVolume: monitorVolume)
        }
        onRecovered?()
    }

    // MARK: - Duplex

    /// One engine, one AUHAL, one clock. The monitor signal never leaves the
    /// render graph: there is no ring buffer, no worker thread, no scheduled
    /// buffer queue, and therefore no drift between a capture clock and a
    /// playback clock. The analysis tap hangs off the same input node and is
    /// purely an observer — it cannot add latency to what is heard.
    private func startDuplex(deviceID: AudioDeviceID, monitorVolume: Float) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try bind(audioUnit: input.audioUnit!, to: deviceID, label: "input")

        // Input nodes don't perform format conversion; their hardware input
        // format must therefore be used verbatim by both the tap and the
        // monitor connection.
        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw NSError(domain: "Fretlight.Audio", code: -1, userInfo: [NSLocalizedDescriptionKey: "The selected device has no active input stream."])
        }
        // Note: on a device that presents more than two input channels, the
        // mixer downmixes all of them into the monitor. The analysis path
        // still reads channel 0 alone, so detection is unaffected, but a
        // multi-channel interface exposing (say) a processed pair and a dry DI
        // pair will be heard summed. Selecting a single channel needs a matrix
        // mixer in the graph: the AUHAL's own channel map is accepted by the
        // unit but AVAudioEngine caches the node's format and never re-reads
        // it, so the two ends disagree.
        let mixer = engine.mainMixerNode
        let sink = CaptureSink(analysisRing: analysisRing, monitorRing: nil, chordRing: chordRing, recordingRing: recordingRingIfAvailable)
        // The makeup-gain stage sits only on the monitor leg of the fan-out
        // below, in series before the mixer — the sink's leg is a separate
        // parallel connection straight off `input`, so this never touches
        // what the detectors see.
        let monitorGain = Self.makeMonitorGainStage(volume: monitorVolume)
        engine.attach(sink.node)
        engine.attach(monitorGain)
        // One source, two destinations: the mixer (via the gain stage)
        // carries what is heard, the sink feeds the detector. Neither can
        // delay the other.
        engine.connect(input, to: [AVAudioConnectionPoint(node: monitorGain, bus: 0),
                                   AVAudioConnectionPoint(node: sink.node, bus: 0)],
                       fromBus: 0, format: hardwareFormat)
        engine.connect(monitorGain, to: mixer, format: hardwareFormat)
        // Neutral output: the slider rides the monitor leg's own input bus,
        // and this mixer is about to become a summing point for sample
        // playback as well.
        mixer.outputVolume = 1

        let frames = AudioDeviceEnumerator.bufferFrameSize(deviceID).map(Int.init) ?? 512
        let analysis = makeAnalysisWorker(directMonitoring: true)
        let chord = makeChordWorker()
        captureSink = sink

        engine.prepare()
        do { try engine.start() }
        catch {
            engine.stop()
            throw error
        }

        captureEngine = engine
        inputNode = input
        monitorLevel = monitorGain
        observeConfigurationChanges(of: engine)
        analysis.start(sampleRate: hardwareFormat.sampleRate, bufferSize: frames)
        chord.start(sampleRate: hardwareFormat.sampleRate)
        startSampleRecorderIfEnabled(sampleRate: hardwareFormat.sampleRate)
    }

    // MARK: - Split

    private func startSplit(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID, monitorVolume: Float) throws {
        // --- Capture graph: bound only to the input device. ---
        let capture = AVAudioEngine()
        let input = capture.inputNode
        try bind(audioUnit: input.audioUnit!, to: inputDeviceID, label: "input")
        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw NSError(domain: "Fretlight.Audio", code: -1, userInfo: [NSLocalizedDescriptionKey: "The selected device has no active input stream."])
        }

        // --- Playback graph: bound only to the output device. ---
        let playback = AVAudioEngine()
        try bind(audioUnit: playback.outputNode.audioUnit!, to: outputDeviceID, label: "output")

        let frames = AudioDeviceEnumerator.bufferFrameSize(inputDeviceID).map(Int.init) ?? 512
        let monitorFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: 1)!
        // Two capture periods of reserve: the playback callback can fire at any
        // phase relative to the capture callback, so anything less regularly
        // asks for audio that has not arrived. The trim ceiling then sits four
        // further periods above that, clear of the working range.
        let renderer = MonitorRenderer(ring: monitorRing,
                                       format: monitorFormat,
                                       targetBacklogFrames: frames * 2,
                                       trimThresholdFrames: frames * 6)
        // Same makeup-gain stage as the duplex path, in series after the
        // renderer and before the mixer — the ring it pulls from was
        // already filled pre-gain by `CaptureSink`, so this is monitor-only
        // here too.
        let monitorGain = Self.makeMonitorGainStage(volume: monitorVolume)
        playback.attach(renderer.node)
        playback.attach(monitorGain)
        playback.connect(renderer.node, to: monitorGain, format: monitorFormat)
        playback.connect(monitorGain, to: playback.mainMixerNode, format: monitorFormat)
        // Neutral, for the same reason as the duplex path above.
        playback.mainMixerNode.outputVolume = 1

        let analysis = makeAnalysisWorker(directMonitoring: false)
        let chord = makeChordWorker()
        let sink = CaptureSink(analysisRing: analysisRing, monitorRing: monitorRing, chordRing: chordRing, recordingRing: recordingRingIfAvailable)
        capture.attach(sink.node)
        capture.connect(input, to: sink.node, format: hardwareFormat)
        captureSink = sink

        capture.prepare()
        playback.prepare()
        do {
            try capture.start()
            try playback.start()
        } catch {
            capture.stop()
            playback.stop()
            throw error
        }

        captureEngine = capture
        playbackEngine = playback
        inputNode = input
        monitorRenderer = renderer
        monitorLevel = monitorGain
        observeConfigurationChanges(of: capture)
        observeConfigurationChanges(of: playback)
        analysis.start(sampleRate: hardwareFormat.sampleRate, bufferSize: frames)
        chord.start(sampleRate: hardwareFormat.sampleRate)
        startSampleRecorderIfEnabled(sampleRate: hardwareFormat.sampleRate)
    }

    // MARK: - Shared graph pieces

    private func bind(audioUnit: AudioUnit, to deviceID: AudioDeviceID, label: String) throws {
        var device = deviceID
        let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw NSError(domain: "Fretlight.Audio", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not select the \(label) device."])
        }
    }

    private func makeAnalysisWorker(directMonitoring: Bool) -> AudioAnalysisWorker {
        let analysis = AudioAnalysisWorker(ring: analysisRing, sensitivity: sensitivity)
        let timebase = timebase
        analysis.onUpdate = { [weak self] state, captureTime in
            Task { @MainActor [weak self] in
                var measured = state
                let elapsed = mach_absolute_time() - captureTime
                measured.latencyMilliseconds = Double(elapsed) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
                measured.isDirectMonitoring = directMonitoring
                self?.onUpdate?(measured)
            }
        }
        worker = analysis
        return analysis
    }

    /// Built and started alongside `worker` on every graph (re)build, same
    /// as it, but whether it actually costs anything is controlled
    /// separately by `setChordDetectionEnabled` — see `ChordAnalysisWorker`.
    private func makeChordWorker() -> ChordAnalysisWorker {
        let chord = ChordAnalysisWorker(ring: chordRing)
        chord.onUpdate = { [weak self] state in
            Task { @MainActor [weak self] in self?.onChordUpdate?(state) }
        }
        chord.setEnabled(chordDetectionEnabled)
        chordWorker = chord
        return chord
    }

    /// Safe to call from any thread — both the stored flag write and the
    /// worker's own flag are atomic-guarded internally.
    func setChordDetectionEnabled(_ value: Bool) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.chordDetectionEnabled = value
            self.chordWorker?.setEnabled(value)
        }
    }

#if DEBUG
    /// Safe to call from any thread, same as `setChordDetectionEnabled`. The
    /// recorder is a whole drain loop rather than a flag check, so it is not
    /// merely gated when disabled — it is not running at all.
    func setSampleRecordingEnabled(_ value: Bool) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.sampleRecordingEnabled = value
            if value {
                self.startSampleRecorderIfEnabled(sampleRate: self.currentSampleRate)
            } else {
                self.sampleRecorder.stop()
            }
        }
    }

    /// A graph rebuild restarts the recorder on the new rate, but only if the
    /// capture screen had it running — a device change mid-session should not
    /// quietly switch recording on.
    private func startSampleRecorderIfEnabled(sampleRate: Double) {
        currentSampleRate = sampleRate
        guard sampleRecordingEnabled, sampleRate > 0 else { return }
        sampleRecorder.stop()
        sampleRecorder.start(sampleRate: sampleRate)
    }
#else
    private func startSampleRecorderIfEnabled(sampleRate: Double) {}
#endif

    /// A USB interface — especially a DSP-heavy one like a modeling
    /// processor — can renegotiate its own format/sample-rate/buffer layout
    /// mid-stream (e.g. on a patch change). When that happens, Core Audio
    /// posts this notification and can leave the engine's render graph
    /// stale. Restarting rebuilds it, but a restart that races the device's
    /// own (asynchronous) teardown can itself fail and re-trigger this same
    /// notification — with no debounce that becomes an unbounded restart
    /// loop. This coalesces bursts of the notification into a single
    /// delayed attempt, and gives up after a few failures in a short window
    /// rather than spinning forever — a device that keeps failing to
    /// restart needs a person to look at it, not an infinite loop.
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        let token = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self, weak engine] _ in
            guard let engine else { return }
            self?.scheduleRestart(for: engine)
        }
        configChangeObservers.append(token)
    }

    private func scheduleRestart(for engine: AVAudioEngine) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            // Notifications from an engine that has already been stopped are
            // normal during teardown. They must not start a fresh recovery
            // loop for a healthy, newly-created engine.
            guard self.captureEngine === engine || self.playbackEngine === engine else { return }
            // Our own start-up churn, not the device renegotiating under us.
            // The graph was built after this change, so it is already current.
            guard Date() >= self.settledAfter else { return }
            self.pendingRestart?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.attemptRestart() }
            self.pendingRestart = work
            // Rebuild after the device has finished its own configuration
            // change. This is the recovery path that keeps the input tap
            // alive on interfaces which renegotiate mid-stream.
            self.controlQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func attemptRestart() {
        guard let inputID = currentInputDeviceID, let outputID = currentOutputDeviceID else { return }
        let now = Date()
        if now.timeIntervalSince(restartWindowStart) > 10 {
            restartWindowStart = now
            restartAttempts = 0
        }
        restartAttempts += 1
        guard restartAttempts <= 3 else {
            reportConnectionFailureIfNeeded()
            return
        }
        onReconnecting?()
        do {
            try startSynchronously(inputDeviceID: inputID, outputDeviceID: outputID, monitorVolume: currentMonitorVolume)
        } catch {
            reportConnectionFailureIfNeeded()
        }
    }

    private func reportConnectionFailureIfNeeded() {
        guard !didReportConnectionFailure else { return }
        // The selected hardware is still enumerated: this was an engine
        // reconfiguration failure, not a disconnected device. Keep recovery
        // silent rather than falsely claiming the connection was lost.
        guard selectedDevicesAreUnavailable() else {
            restartAttempts = 0
            restartWindowStart = .distantPast
            return
        }
        didReportConnectionFailure = true
        onError?("Lost a stable connection to the audio device after repeated attempts to recover. Try reselecting it, or disconnecting and reconnecting it.")
    }

    private func selectedDevicesAreUnavailable() -> Bool {
        guard let inputID = currentInputDeviceID, let outputID = currentOutputDeviceID else { return true }
        let inputExists = AudioDeviceEnumerator.inputDevices().contains { $0.id == inputID }
        let outputExists = AudioDeviceEnumerator.outputDevices().contains { $0.id == outputID }
        return !inputExists || !outputExists
    }

    /// Safe to call from any thread — SensitivitySettings does its own
    /// locking, unlike currentMonitorVolume/monitorLevel below which need
    /// the control queue's serialization.
    func setSensitivity(_ value: Double) {
        sensitivity.value = value
    }

    func setMonitorVolume(_ value: Float) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.currentMonitorVolume = min(max(value, 0), 1)
            self.monitorLevel?.globalGain = Self.monitorGainDB(forVolume: self.currentMonitorVolume)
        }
    }

    func stop() {
        controlQueue.async { [weak self] in self?.stopSynchronously() }
    }

    private func stopSynchronously() {
        pendingRestart?.cancel()
        pendingRestart = nil
        configChangeObservers.forEach(NotificationCenter.default.removeObserver)
        configChangeObservers.removeAll()
        worker?.stop()
        chordWorker?.stop()
#if DEBUG
        sampleRecorder.stop()
#endif
        captureEngine?.stop()
        captureEngine?.reset()
        playbackEngine?.stop()
        playbackEngine?.reset()
        worker = nil
        chordWorker = nil
        monitorRenderer = nil
        captureSink = nil
        inputNode = nil
        monitorLevel = nil
        captureEngine = nil
        playbackEngine = nil
    }
}
