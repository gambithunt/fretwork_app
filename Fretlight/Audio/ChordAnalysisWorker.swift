import Accelerate
import Foundation
import Darwin

/// Mirrors `AudioAnalysisWorker`'s tap-and-poll shape but reads its own
/// `RingBuffer` — per that type's single-producer/single-consumer rule, a
/// second consumer on the *same* ring would corrupt the shared read cursor,
/// so this gets its own instance fed from the same `CaptureSink` tap — at a
/// wider window and slower cadence: a chord is read by ear as a sustained
/// event, not chased frame-by-frame like a tuner needle, and the wider
/// window is what `ChordDetector`'s chroma FFT needs for semitone
/// resolution down at the low E string.
final class ChordAnalysisWorker: @unchecked Sendable {
    static let windowSize = ChordAnalysisWorker.hopSize * 2
    static let hopSize = 4096

    private let ring: RingBuffer
    private let queue = DispatchQueue(label: "com.fretlight.chord-analysis", qos: .userInitiated)
    private let detector: ChordDetector
    private var window = Array(repeating: Float.zero, count: ChordAnalysisWorker.windowSize)
    private var incoming = Array(repeating: Float.zero, count: ChordAnalysisWorker.hopSize)
    private var lastMatch: ChordMatch?
    private var lastDetection: ContinuousClock.Instant?
    private var running: Int32 = 0
    /// Set from `AppState`'s Notes/Chords toggle. Left as a flag checked by
    /// an already-running thread rather than starting/stopping the thread
    /// (or worse, the audio graph) on every toggle — the graph restart path
    /// exists to recover from real device failures and triggers a visible
    /// "Reconnecting" state; a UI mode switch shouldn't pay that cost.
    private var enabled: Int32 = 0
    var onUpdate: (@Sendable (ChordDisplayState) -> Void)?

    init(ring: RingBuffer, windowSize: Int = ChordAnalysisWorker.windowSize) {
        self.ring = ring
        detector = ChordDetector(windowSize: windowSize)
    }

    func start(sampleRate: Double) {
        OSAtomicCompareAndSwap32Barrier(0, 1, &running)
        queue.async { [weak self] in self?.consume(sampleRate: sampleRate) }
    }

    func stop() { OSAtomicCompareAndSwap32Barrier(1, 0, &running) }

    func setEnabled(_ value: Bool) {
        let target: Int32 = value ? 1 : 0
        while true {
            let current = OSAtomicAdd32Barrier(0, &enabled)
            if current == target { break }
            if OSAtomicCompareAndSwap32Barrier(current, target, &enabled) { break }
        }
        if !value { onUpdate?(ChordDisplayState()) }
    }

    private func consume(sampleRate: Double) {
        while OSAtomicAdd32Barrier(0, &running) == 1 {
            guard OSAtomicAdd32Barrier(0, &enabled) == 1 else {
                // O(1) — just advances the read cursor, no copy — so the
                // ring doesn't sit there silently filling and dropping
                // writes while Notes mode has nothing draining it.
                ring.trimBacklog(toAtMost: 0)
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            let didRead = incoming.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: Self.hopSize) }
            guard didRead else { Thread.sleep(forTimeInterval: 0.01); continue }
            window.withUnsafeMutableBufferPointer { pointer in
                let keep = Self.windowSize - Self.hopSize
                memmove(pointer.baseAddress!, pointer.baseAddress! + Self.hopSize, keep * MemoryLayout<Float>.stride)
                _ = incoming.withUnsafeBufferPointer { newer in
                    memmove(pointer.baseAddress! + keep, newer.baseAddress!, Self.hopSize * MemoryLayout<Float>.stride)
                }
            }
            let rms = window.withUnsafeBufferPointer { data -> Float in
                var value: Float = 0; vDSP_rmsqv(data.baseAddress!, 1, &value, vDSP_Length(data.count)); return value
            }
            let now = ContinuousClock.now
            // -50dBFS: below what a strum leaves ringing, above the noise floor.
            guard rms > 0.003, let match = detector.detect(samples: window, sampleRate: sampleRate) else {
                // A brief hold through the natural dip between strums —
                // same idea as AudioAnalysisWorker's note hold, just longer
                // because a held chord decays slower than a single note.
                if let lastDetection, now - lastDetection < .milliseconds(400), let held = lastMatch {
                    onUpdate?(ChordDisplayState(chord: held, level: rms))
                } else {
                    lastMatch = nil
                    onUpdate?(ChordDisplayState(chord: nil, level: rms))
                }
                continue
            }
            lastMatch = match
            lastDetection = now
            onUpdate?(ChordDisplayState(chord: match, level: rms))
        }
    }
}
