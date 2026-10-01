#if DEBUG
import Foundation

/// DEBUG-only `-FretworkCaptureDump` writer. Consumes its **own** `RingBuffer` —
/// fed by the same `CaptureSink` that feeds the analysis/chord rings, never a
/// second reader on an existing ring — and keeps the last ~20 s of raw mono
/// input. `stopAndTake()` returns those frames; `writeWAV` serialises them as a
/// Float32 WAV whose header carries the real capture rate.
///
/// Not `@MainActor`: the reader runs on a utility queue and owns `frames` under
/// a lock, so it never touches the main actor and never allocates on the audio
/// thread (the producer is `CaptureSink`'s realtime callback, which only calls
/// `ring.write`).
final class CaptureDumpWriter: @unchecked Sendable {
    private let ring: RingBuffer
    private let queue = DispatchQueue(label: "com.fretwork.capture-dump", qos: .utility)
    private let lock = NSLock()
    private var frames: [Float] = []
    private var running = false
    /// 20 s at 48 kHz — a fixed upper bound so the reader never needs the real
    /// rate; `flush` trims to the exact 20 s at the real rate before writing.
    private let maxFrames = 20 * 48_000

    init(ring: RingBuffer) {
        self.ring = ring
    }

    func start() {
        lock.lock()
        running = true
        lock.unlock()
        queue.async { [weak self] in self?.readLoop() }
    }

    /// Stops the reader and returns the captured frames (≤ the last 20 s).
    func stopAndTake() -> [Float] {
        lock.lock()
        running = false
        lock.unlock()
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    private func readLoop() {
        var buffer = [Float](repeating: 0, count: 1024)
        while true {
            lock.lock()
            let active = running
            lock.unlock()
            guard active else { return }

            let didRead = buffer.withUnsafeMutableBufferPointer {
                ring.read(into: $0.baseAddress!, count: 1024)
            }
            if didRead {
                lock.lock()
                frames.append(contentsOf: buffer)
                let excess = frames.count - maxFrames
                if excess > 0 { frames.removeFirst(excess) }
                lock.unlock()
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    /// Serialises `frames` as a mono Float32 WAV (WAVE_FORMAT_IEEE_FLOAT).
    static func writeWAV(_ frames: [Float], sampleRate: Double, to url: URL) throws {
        var data = Data()
        func appendASCII(_ string: String) { data.append(string.data(using: .ascii)!) }
        func appendLE32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendLE16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        let dataSize = UInt32(frames.count * MemoryLayout<Float>.size)
        appendASCII("RIFF")
        appendLE32(36 + dataSize)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendLE32(16)
        appendLE16(3)                       // IEEE float
        appendLE16(1)                       // mono
        appendLE32(UInt32(sampleRate))
        appendLE32(UInt32(sampleRate) * 4)  // byte rate
        appendLE16(4)                       // block align
        appendLE16(32)                      // bits per sample
        appendASCII("data")
        appendLE32(dataSize)
        frames.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url)
    }
}
#endif
