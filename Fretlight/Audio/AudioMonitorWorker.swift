import AVFoundation
import Foundation

private final class MonitorFrameCounter: @unchecked Sendable {
    private var raw: Int32 = 0
    var value: Int32 { OSAtomicAdd32Barrier(0, &raw) }
    func add(_ delta: Int32) { _ = OSAtomicAdd32Barrier(delta, &raw) }
}

/// Schedules direct-monitor buffers away from the input tap. Buffer creation and
/// AVAudioPlayerNode calls are intentionally never performed on a realtime thread.
final class AudioMonitorWorker: @unchecked Sendable {
    private let ring: RingBuffer
    private let player: AVAudioPlayerNode
    private let format: AVAudioFormat
    private let queuedFrames = MonitorFrameCounter()
    private let queue = DispatchQueue(label: "com.fretlight.monitor", qos: .userInitiated)
    private var running: Int32 = 0
    private let batchFrames = 512
    /// 4 buffers deep (~46ms at 44.1kHz). The previous 2-buffer cap sat right
    /// at its own boundary almost constantly in steady state, which — combined
    /// with the busy-spin bug above — meant this throttle path was hit on
    /// nearly every iteration. More headroom means the normal case rarely
    /// touches the throttle at all.
    private let queueCapFrames: Int32 = 2_048

    init(ring: RingBuffer, player: AVAudioPlayerNode, format: AVAudioFormat) {
        self.ring = ring
        self.player = player
        self.format = format
    }

    func start() {
        OSAtomicCompareAndSwap32Barrier(0, 1, &running)
        queue.async { [weak self] in self?.consume() }
    }

    func stop() { OSAtomicCompareAndSwap32Barrier(1, 0, &running) }

    private func consume() {
        var samples = Array(repeating: Float.zero, count: batchFrames)
        while OSAtomicAdd32Barrier(0, &running) == 1 {
            // Check the player's queue BEFORE touching the ring. This used
            // to check AFTER an unconditional read, with only a 2-buffer cap
            // — a boundary steady-state playback sits right on almost
            // constantly — so on failure it discarded the samples it had
            // just removed from the ring and looped straight back with no
            // sleep. That busy-spin was pegging a CPU core hard enough to
            // starve Core Audio's real-time I/O thread ("skipping cycle due
            // to overload" / "out of order message" in Console), which
            // cascaded into -10877 and the eventual disconnect — regardless
            // of which physical device was selected.
            guard queuedFrames.value < queueCapFrames else {
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            let hasSamples = samples.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: batchFrames) }
            guard hasSamples else { Thread.sleep(forTimeInterval: 0.002); continue }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(batchFrames)),
                  let destination = buffer.floatChannelData?[0] else { continue }
            buffer.frameLength = AVAudioFrameCount(batchFrames)
            destination.update(from: samples, count: batchFrames)
            queuedFrames.add(Int32(batchFrames))
            player.scheduleBuffer(buffer) { [queuedFrames, batchFrames] in
                queuedFrames.add(-Int32(batchFrames))
            }
        }
    }
}
