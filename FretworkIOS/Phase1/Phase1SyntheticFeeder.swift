#if DEBUG
import Darwin
import Foundation

struct Phase1SyntheticTone: Sendable {
    var frequency: Double = 440
    var amplitude: Float = 0.8
    var sampleRate: Double = 48_000

    func samples(frameCount: Int, startingFrame: UInt64) -> [Float] {
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { index in
            let frame = Double(startingFrame + UInt64(index))
            return amplitude * Float(sin(2 * Double.pi * frequency * frame / sampleRate))
        }
    }
}

/// Deterministic source for Simulator and tests. It writes synthetic mono PCM
/// into the same analysis pipeline that the manual microphone callbacks use,
/// without touching `AVAudioSession` or hardware.
final class Phase1SyntheticFeeder: @unchecked Sendable {
    private let pipeline: Phase1AnalysisPipeline
    private let tone: Phase1SyntheticTone
    private let frameCount: Int
    private let intervalNanoseconds: UInt64
    private var task: Task<Void, Never>?
    private var nextFrame: UInt64 = 0

    init(
        pipeline: Phase1AnalysisPipeline,
        tone: Phase1SyntheticTone = Phase1SyntheticTone(),
        frameCount: Int = 1024
    ) {
        self.pipeline = pipeline
        self.tone = tone
        self.frameCount = frameCount
        intervalNanoseconds = UInt64(Double(frameCount) / tone.sampleRate * 1_000_000_000)
    }

    func start() {
        guard task == nil else { return }
        pipeline.start(sampleRate: tone.sampleRate, bufferSize: frameCount)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.feedOneChunk()
                try? await Task.sleep(nanoseconds: self.intervalNanoseconds)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        pipeline.stop()
    }

    func feed(chunks: Int) {
        pipeline.start(sampleRate: tone.sampleRate, bufferSize: frameCount)
        for _ in 0..<chunks { feedOneChunk() }
    }

    private func feedOneChunk() {
        let samples = tone.samples(frameCount: frameCount, startingFrame: nextFrame)
        samples.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                // Host-time stamp, same units as the microphone sink, so the
                // synthetic path reports a comparable `latencyMs` rather than
                // a sample index that would dwarf the clock.
                pipeline.write(samples: baseAddress, frameCount: samples.count, captureTime: mach_absolute_time())
            }
        }
        nextFrame += UInt64(frameCount)
    }
}

#endif
