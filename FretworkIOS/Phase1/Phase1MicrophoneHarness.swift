import AVFoundation
import Darwin
import Foundation

enum Phase1MicrophoneHarnessError: LocalizedError, Equatable {
    case unsupportedMode
    case permissionDenied
    case noFloatChannelData
    case noInputBuffer

    var errorDescription: String? {
        switch self {
        case .unsupportedMode: "This capture mode is not supported by the manual microphone harness."
        case .permissionDenied: "Microphone permission is denied. Enable microphone access in Settings to run the manual Phase 1 capture spike."
        case .noFloatChannelData: "The input callback did not provide Float32 channel data."
        case .noInputBuffer: "The input callback did not provide audio buffers."
        }
    }
}

@MainActor
final class Phase1MicrophoneHarness: Phase1ManualCaptureSource {
    private var engine: AVAudioEngine?
    private var sinkNode: AVAudioSinkNode?
    private var pipeline: Phase1AnalysisPipeline?

    /// `AVAudioSinkNodeReceiverBlock` is imported as
    /// `NS_SWIFT_NONSENDABLE`. A closure literal written inside this
    /// `@MainActor` type therefore inherits MainActor isolation and carries a
    /// runtime executor check. The first realtime callback fails that check and
    /// traps, freezing the app with zero callbacks and zero updates. Build the
    /// block in a `nonisolated` static function so it is created off the
    /// actor; the pipeline capture stays weak, exactly as before.
    nonisolated static func makeSinkBlock(pipeline: Phase1AnalysisPipeline) -> AVAudioSinkNodeReceiverBlock {
        { [weak pipeline] timeStamp, frameCount, audioBufferList in
            guard let firstBuffer = audioBufferList.pointee.mBuffers.mData else { return noErr }
            let samples = firstBuffer.assumingMemoryBound(to: Float.self)
            // Host-time stamp of when this buffer arrived from the input HAL,
            // read here on the realtime thread (`mach_absolute_time` is a vDSO
            // call: no lock, no allocation). `mHostTime` is normally valid for a
            // sink callback; fall back to the current clock when it is zero
            // (e.g. synthetic timestamp structs in tests). This is the start of
            // the interval `latencyMs` reports — not the sample position.
            let hostTime = timeStamp.pointee.mHostTime
            let captureTime = hostTime != 0 ? hostTime : mach_absolute_time()
            pipeline?.write(samples: samples, frameCount: Int(frameCount), captureTime: captureTime)
            return noErr
        }
    }

    func start(mode: Phase1CaptureMode, pipeline: Phase1AnalysisPipeline) async throws {
        guard mode == .microphoneSink else {
            throw Phase1MicrophoneHarnessError.unsupportedMode
        }
        try await ensurePermissionGranted()
        // Stop may have been requested during the system permission prompt.
        // Bail out before configuring any audio hardware.
        try Task.checkCancellation()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Validate input format.
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            cleanup()
            throw Phase1MicrophoneHarnessError.noFloatChannelData
        }
        guard format.channelCount > 0, format.sampleRate > 0 else {
            cleanup()
            throw Phase1MicrophoneHarnessError.noInputBuffer
        }

        // Set references before any fallible setup so cleanup() can undo.
        self.pipeline = pipeline
        self.engine = engine
        pipeline.start(sampleRate: format.sampleRate, bufferSize: 1024)

        do {
            switch mode {
            case .microphoneSink:
                let sink = AVAudioSinkNode(receiverBlock: Self.makeSinkBlock(pipeline: pipeline))
                engine.attach(sink)
                engine.connect(input, to: sink, format: format)
                sinkNode = sink

            case .synthetic:
                throw Phase1MicrophoneHarnessError.unsupportedMode
            }

            engine.prepare()
            try engine.start()
        } catch {
            cleanup()
            throw error
        }
    }

    func stop() {
        cleanup()
    }

    /// Session-level fixed latencies for the diagnostic log. Read after the
    /// engine has started so `inputLatency`/`ioBufferDuration` reflect the
    /// active route rather than the pre-activation defaults.
    func sessionMetrics() -> Phase1SessionMetrics? {
        let session = AVAudioSession.sharedInstance()
        return Phase1SessionMetrics(
            inputLatency: session.inputLatency,
            ioBufferDuration: session.ioBufferDuration
        )
    }

    private func cleanup() {
        if let engine {
            engine.stop()
            if let sinkNode {
                engine.disconnectNodeInput(sinkNode)
                engine.detach(sinkNode)
            }
        }
        sinkNode = nil
        engine = nil
        pipeline?.stop()
        pipeline = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func ensurePermissionGranted() async throws {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return
            case .denied:
                throw Phase1MicrophoneHarnessError.permissionDenied
            case .undetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
                guard granted else { throw Phase1MicrophoneHarnessError.permissionDenied }
            @unknown default:
                throw Phase1MicrophoneHarnessError.permissionDenied
            }
        } else {
            throw Phase1MicrophoneHarnessError.permissionDenied
        }
    }
}
