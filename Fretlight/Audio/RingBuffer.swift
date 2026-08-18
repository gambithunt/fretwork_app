import Foundation
import Darwin

/// Preallocated SPSC storage. The producer is the AVAudioEngine tap; the
/// consumer is AudioAnalysisWorker. OSAtomic gives acquire/release barriers
/// without a mutex or allocation on the realtime thread.
final class RingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let samples: UnsafeMutablePointer<Float>
    private var writeIndex: Int32 = 0
    private var readIndex: Int32 = 0
    private var latestCaptureTime: Int64 = 0

    init(capacity: Int = 32_768) {
        self.capacity = capacity
        samples = .allocate(capacity: capacity)
        samples.initialize(repeating: 0, count: capacity)
    }

    deinit { samples.deinitialize(count: capacity); samples.deallocate() }

    /// Realtime-safe: caller supplies a stable buffer; overflow drops the incoming
    /// buffer. The producer never mutates the consumer-owned read cursor.
    func write(_ source: UnsafePointer<Float>, count: Int, captureTime: UInt64) {
        let write = Int(OSAtomicAdd32Barrier(0, &writeIndex))
        let read = Int(OSAtomicAdd32Barrier(0, &readIndex))
        let available = capacity - (write - read)
        guard count <= available else { return }
        for index in 0..<count { samples[(write + index) % capacity] = source[index] }
        OSAtomicAdd32Barrier(Int32(count), &writeIndex)
        var old = OSAtomicAdd64Barrier(0, &latestCaptureTime)
        while !OSAtomicCompareAndSwap64Barrier(old, Int64(bitPattern: captureTime), &latestCaptureTime) {
            old = OSAtomicAdd64Barrier(0, &latestCaptureTime)
        }
    }

    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        let read = Int(OSAtomicAdd32Barrier(0, &readIndex))
        let write = Int(OSAtomicAdd32Barrier(0, &writeIndex))
        guard write - read >= count else { return false }
        for index in 0..<count { destination[index] = samples[(read + index) % capacity] }
        OSAtomicAdd32Barrier(Int32(count), &readIndex)
        return true
    }

    func currentCaptureTime() -> UInt64 { UInt64(bitPattern: OSAtomicAdd64Barrier(0, &latestCaptureTime)) }

    /// Bounds how far the reader can fall behind the writer. Without this,
    /// two producer/consumer clocks that aren't perfectly locked (e.g. two
    /// different physical audio devices) drift apart monotonically: the
    /// backlog — and therefore the delay between capture and playback —
    /// grows for as long as the stream runs. Only the reader may call this,
    /// matching the existing invariant that the read cursor is reader-owned.
    func trimBacklog(toAtMost maxBacklog: Int) {
        let write = Int(OSAtomicAdd32Barrier(0, &writeIndex))
        let read = Int(OSAtomicAdd32Barrier(0, &readIndex))
        let backlog = write - read
        guard backlog > maxBacklog else { return }
        OSAtomicAdd32Barrier(Int32(backlog - maxBacklog), &readIndex)
    }
}
