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

    /// A pick attack must raise a hop's RMS to this multiple of the previous
    /// hop's before it counts as a new strum rather than the same chord
    /// still ringing — the whole point being to tell "a new chord just got
    /// hit" apart from "these same strings are decaying, so their balance
    /// (and therefore the chroma) is drifting". Reasoned from the shape of
    /// a plucked/strummed attack (much sharper than any natural decay), not
    /// measured against a real guitar — needs the same real-recording
    /// tuning pass `SensitivitySettings` got.
    private static let onsetRatio: Float = 1.6
    /// How long after an onset a fresh detection is still allowed to
    /// *replace* the locked chord, rather than just being computed and
    /// discarded. Covers the pick-noise-heavy first moment of a strum
    /// settling into a clean, confidently-classifiable spectrum.
    private static let settleWindow = Duration.milliseconds(150)
    /// -50dBFS: below what a strum leaves ringing, above the noise floor.
    private static let silenceFloor: Float = 0.003
    /// How long to keep showing the locked chord after the signal has
    /// dropped below `silenceFloor` entirely, before actually clearing it —
    /// long enough to cover the gap between strums of the same chord
    /// without reading as stuck.
    private static let silenceHold = Duration.milliseconds(1200)

    private let ring: RingBuffer
    private let queue = DispatchQueue(label: "com.fretlight.chord-analysis", qos: .userInitiated)
    private let detector: ChordDetector
    private var window = Array(repeating: Float.zero, count: ChordAnalysisWorker.windowSize)
    private var incoming = Array(repeating: Float.zero, count: ChordAnalysisWorker.hopSize)
    /// The chord currently on screen. Only an onset (see `onsetRatio`) is
    /// allowed to replace it — plain decay/sustain, even while still above
    /// `silenceFloor`, never is. That's what stops the reading drifting or
    /// flickering as a strum's own strings die away at different rates.
    private var lockedMatch: ChordMatch?
    private var previousRMS: Float = 0
    private var settleUntil: ContinuousClock.Instant?
    private var silentSince: ContinuousClock.Instant?
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
        // The actual reset of lockedMatch/previousRMS/etc. happens inside
        // consume(), on its own thread, the next time it observes `enabled`
        // go to 0 — those are plain (non-atomic) fields the worker thread
        // owns, and writing them from here (this can be called from any
        // thread) would race it.
        if !value { onUpdate?(ChordDisplayState()) }
    }

    private func consume(sampleRate: Double) {
        while OSAtomicAdd32Barrier(0, &running) == 1 {
            guard OSAtomicAdd32Barrier(0, &enabled) == 1 else {
                // O(1) — just advances the read cursor, no copy — so the
                // ring doesn't sit there silently filling and dropping
                // writes while Notes mode has nothing draining it.
                ring.trimBacklog(toAtMost: 0)
                // Owned entirely by this thread (see setEnabled), so it's
                // safe to just reset every idle tick rather than tracking
                // the disable edge separately.
                lockedMatch = nil
                previousRMS = 0
                settleUntil = nil
                silentSince = nil
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
            defer { previousRMS = rms }

            guard rms > Self.silenceFloor else {
                // Held through the gap between strums rather than dropping
                // out immediately — only once it's been quiet for
                // `silenceHold` is the chord actually cleared.
                if silentSince == nil { silentSince = now }
                let held = (silentSince.map { now - $0 < Self.silenceHold } ?? true) ? lockedMatch : nil
                if held == nil { lockedMatch = nil }
                onUpdate?(ChordDisplayState(chord: held, level: rms))
                continue
            }
            silentSince = nil

            // A hop whose RMS jumped up from the previous one is a fresh
            // pick attack, not the same chord still ringing — that's the
            // one event allowed to override a locked-in reading. Plain
            // decay/sustain, even while comfortably above the floor, never
            // is; that's what stops the reading drifting as a strum's own
            // strings die away at different rates.
            if rms > previousRMS * Self.onsetRatio { settleUntil = now + Self.settleWindow }
            let stillSettling = lockedMatch == nil || (settleUntil.map { now < $0 } ?? false)

            guard stillSettling, let match = detector.detect(samples: window, sampleRate: sampleRate) else {
                onUpdate?(ChordDisplayState(chord: lockedMatch, level: rms))
                continue
            }
            lockedMatch = match
            onUpdate?(ChordDisplayState(chord: match, level: rms))
        }
    }
}
