import AVFoundation
import AudioToolbox
import Foundation
import Darwin

/// Captures from `inputDeviceID` and monitors out to `outputDeviceID`.
///
/// These intentionally live on two separate `AVAudioEngine` instances. A
/// single engine's `inputNode` and `outputNode` share one underlying AUHAL
/// (confirmed via `audioUnit` identity), so `kAudioOutputUnitProperty_CurrentDevice`
/// can only bind that unit to *one* physical device — trying to point it at
/// an input device and then a different output device makes the second call
/// fail (that's the "Could not select the output device." error). Two
/// separate engines each get their own AUHAL, so the devices can differ.
///
/// Monitoring plays through `AVAudioPlayerNode`, scheduling one small mono
/// buffer per capture callback. An earlier version pulled samples through a
/// custom `AVAudioSourceNode` render callback instead; that consistently hit
/// `kAudioUnitErr_InvalidElement` (-10877) on some interfaces from the very
/// first buffer, which pointed at something structurally wrong with that
/// low-level C-callback path rather than a transient device hiccup.
/// `AVAudioPlayerNode` is the standard, far more heavily used AVFoundation
/// API for exactly this "queue up captured audio, play it back" case.
final class AudioEngine: @unchecked Sendable {
    private let controlQueue = DispatchQueue(label: "com.fretlight.audio-control", qos: .userInitiated)
    private var captureEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var playerNode: AVAudioPlayerNode?
    private let analysisRing = RingBuffer()
    private let monitorRing = RingBuffer()
    private var worker: AudioAnalysisWorker?
    private var monitorWorker: AudioMonitorWorker?
    var onUpdate: (@Sendable (PitchDisplayState) -> Void)?
    var onError: (@Sendable (String) -> Void)?
    private var timebase = mach_timebase_info_data_t()
    private var configChangeObservers: [NSObjectProtocol] = []
    private var currentInputDeviceID: AudioDeviceID?
    private var currentOutputDeviceID: AudioDeviceID?
    private var currentMonitorVolume: Float = 0
    private var pendingRestart: DispatchWorkItem?
    private var restartAttempts = 0
    private var restartWindowStart = Date.distantPast

    init() { mach_timebase_info(&timebase) }

    /// Device negotiation can block inside Core Audio; never perform it on the main actor.
    func start(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID, monitorVolume: Float) {
        controlQueue.async { [weak self] in
            guard let self else { return }
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
        stopSynchronously()
        currentInputDeviceID = inputDeviceID
        currentOutputDeviceID = outputDeviceID
        currentMonitorVolume = monitorVolume

        // --- Capture graph: bound only to the input device. ---
        let capture = AVAudioEngine()
        let input = capture.inputNode
        var inputDevice = inputDeviceID
        let inputStatus = AudioUnitSetProperty(input.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &inputDevice, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard inputStatus == noErr else { throw NSError(domain: "Fretlight.Audio", code: Int(inputStatus), userInfo: [NSLocalizedDescriptionKey: "Could not select the input device."]) }
        // Input nodes don't perform format conversion; their hardware input format
        // must therefore be used verbatim by the tap.
        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw NSError(domain: "Fretlight.Audio", code: -1, userInfo: [NSLocalizedDescriptionKey: "The selected device has no active input stream."])
        }

        // --- Playback graph: bound only to the output device. ---
        let playback = AVAudioEngine()
        let output = playback.outputNode
        var outputDevice = outputDeviceID
        let outputStatus = AudioUnitSetProperty(output.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &outputDevice, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard outputStatus == noErr else { throw NSError(domain: "Fretlight.Audio", code: Int(outputStatus), userInfo: [NSLocalizedDescriptionKey: "Could not select the output device."]) }

        let monitorFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: 1)!
        let player = AVAudioPlayerNode()
        playback.attach(player)
        playback.connect(player, to: playback.mainMixerNode, format: monitorFormat)
        playback.mainMixerNode.outputVolume = monitorVolume

        let analysis = AudioAnalysisWorker(ring: analysisRing)
        let timebase = timebase
        analysis.onUpdate = { [weak self] state, captureTime in
            Task { @MainActor [weak self] in
                var measured = state
                let elapsed = mach_absolute_time() - captureTime
                measured.latencyMilliseconds = Double(elapsed) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
                self?.onUpdate?(measured)
            }
        }
        worker = analysis
        let analysisRing = analysisRing
        let monitorRing = monitorRing
        input.installTap(onBus: 0, bufferSize: 256, format: hardwareFormat) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let captureTime = mach_absolute_time()
            let count = Int(buffer.frameLength)
            analysisRing.write(channel, count: count, captureTime: captureTime)
            monitorRing.write(channel, count: count, captureTime: captureTime)
        }

        capture.prepare()
        playback.prepare()
        do {
            try capture.start()
            try playback.start()
            player.play()
        } catch {
            input.removeTap(onBus: 0)
            capture.stop()
            playback.stop()
            throw error
        }

        captureEngine = capture
        playbackEngine = playback
        inputNode = input
        playerNode = player
        observeConfigurationChanges(of: capture)
        observeConfigurationChanges(of: playback)
        analysis.start(sampleRate: hardwareFormat.sampleRate, bufferSize: 256)
        let monitor = AudioMonitorWorker(ring: monitorRing, player: player, format: monitorFormat)
        monitorWorker = monitor
        monitor.start()
    }

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
        let token = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.scheduleRestart()
        }
        configChangeObservers.append(token)
    }

    private func scheduleRestart() {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.pendingRestart?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.attemptRestart() }
            self.pendingRestart = work
            // Give the device's own teardown a moment to actually finish
            // before we try to reattach to it — and let a burst of several
            // notifications for the same underlying event collapse into one.
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
            onError?("Lost a stable connection to the audio device after repeated attempts to recover. Try reselecting it, or disconnecting and reconnecting it.")
            return
        }
        do {
            try startSynchronously(inputDeviceID: inputID, outputDeviceID: outputID, monitorVolume: currentMonitorVolume)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func setMonitorVolume(_ value: Float) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.currentMonitorVolume = min(max(value, 0), 1)
            self.playbackEngine?.mainMixerNode.outputVolume = self.currentMonitorVolume
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
        inputNode?.removeTap(onBus: 0)
        worker?.stop()
        monitorWorker?.stop()
        playerNode?.stop()
        captureEngine?.stop()
        captureEngine?.reset()
        playbackEngine?.stop()
        playbackEngine?.reset()
        worker = nil
        monitorWorker = nil
        playerNode = nil
        inputNode = nil
        captureEngine = nil
        playbackEngine = nil
    }
}
