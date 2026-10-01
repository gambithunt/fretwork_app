import Accelerate
import Foundation
import MachO
import Darwin

final class AudioAnalysisWorker: @unchecked Sendable {
    private let ring: RingBuffer
    private let sensitivity: SensitivitySettings
    private let queue = DispatchQueue(label: "com.fretlight.analysis", qos: .userInitiated)
    private let detector = PitchDetector()
    private var window = Array(repeating: Float.zero, count: 2048)
    private var incoming = Array(repeating: Float.zero, count: 1024)
    private var confirmation = NoteConfirmation()
    private var lastFrequency: Double = 0
    private var smoothedCents: Double?
    private var smoothedCentsMIDI: Int?
    private var lastDetection: ContinuousClock.Instant?
    private var lastPublish = ContinuousClock.now
    private var running: Int32 = 0
    /// Set by `reset()`; the consume thread clears the smoothing/median state
    /// on its next iteration, so a pre-gate reading cannot leak out after the
    /// playback gate lifts. Guarded by `resetLock` (a class stored var has no
    /// stable address for `&`, and `OSAtomic*` is deprecated).
    private let resetLock = NSLock()
    private var resetRequested = false
    /// Fixed ring of recent level readings (dB) from frames where no note was
    /// confirmed, so a held note never raises its own floor. The running noise
    /// floor is the ~10th percentile of the last ~8 s of quiet frames — the
    /// same idea as the session logger's floor, but live on the consume thread
    /// and feeding the gate rather than a summary. A preallocated ring keeps
    /// the per-frame cost to one store; the percentile is recomputed only a
    /// few times per second, not on every frame.
    private static let quietRingCap = 256
    private var quietRing = [Float](repeating: -120, count: quietRingCap)
    private var quietRingWrite = 0
    private var quietRingFilled = 0
    private var cachedFloorDb: Double = -60
    private var quietFramesSinceRecompute = 0
    /// Whether the previous published frame carried a current detection; a
    /// frame's floor update runs only when the *previous* frame had none, so
    /// a sustained note cannot pollute the floor.
    private var previousFrameConfirmed = false
    var onUpdate: (@Sendable (PitchDisplayState, UInt64) -> Void)?

    init(ring: RingBuffer, sensitivity: SensitivitySettings) {
        self.ring = ring
        self.sensitivity = sensitivity
    }

    func start(sampleRate: Double, bufferSize: Int) {
        OSAtomicCompareAndSwap32Barrier(0, 1, &running)
        queue.async { [weak self] in self?.consume(sampleRate: sampleRate, bufferSize: bufferSize) }
    }
    func stop() { OSAtomicCompareAndSwap32Barrier(1, 0, &running) }

    /// Requests a state reset on the consume thread. Safe from any thread:
    /// the flag is lock-guarded and the fields it clears are owned by that
    /// thread.
    func reset() {
        resetLock.lock()
        resetRequested = true
        resetLock.unlock()
    }

    /// The ~10th percentile of the filled portion of the quiet ring.
    private static func noiseFloor(ring: [Float], count: Int) -> Double {
        guard count > 0 else { return -60 }
        let filled = ring[..<count]
        let sorted = filled.sorted()
        let index = min(count - 1, max(0, Int(Double(count) * 0.10)))
        return Double(sorted[index])
    }

    private func consume(sampleRate: Double, bufferSize: Int) {
        while OSAtomicAdd32Barrier(0, &running) == 1 {
            let shouldReset: Bool = {
                resetLock.lock()
                defer { resetLock.unlock() }
                let value = resetRequested
                resetRequested = false
                return value
            }()
            if shouldReset {
                confirmation.reset()
                quietRingWrite = 0
                quietRingFilled = 0
                cachedFloorDb = -60
                quietFramesSinceRecompute = 0
                previousFrameConfirmed = false
                lastDetection = nil
                smoothedCents = nil
                smoothedCentsMIDI = nil
                lastFrequency = 0
            }
            // Read the newest chunk into scratch first — only once we know it's
            // available do we slide the window and splice the chunk into the tail.
            // (Writing straight into `window` and then shifting over it would
            // overwrite the samples we just read with stale data, which is what
            // was happening before: the window never actually saw new audio.)
            let didRead = incoming.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 1024) }
            guard didRead else { Thread.sleep(forTimeInterval: 0.002); continue }
            window.withUnsafeMutableBufferPointer { pointer in
                memmove(pointer.baseAddress!, pointer.baseAddress! + 1024, 1024 * MemoryLayout<Float>.stride)
                _ = incoming.withUnsafeBufferPointer { newer in
                    memmove(pointer.baseAddress! + 1024, newer.baseAddress!, 1024 * MemoryLayout<Float>.stride)
                }
            }
            let rms = window.withUnsafeBufferPointer { data -> Float in
                var value: Float = 0; vDSP_rmsqv(data.baseAddress!, 1, &value, vDSP_Length(data.count)); return value
            }
            let result = detector.detect(samples: window, sampleRate: sampleRate, threshold: sensitivity.yinThreshold)
            let now = ContinuousClock.now
            guard now - lastPublish >= .milliseconds(33) else { continue }
            lastPublish = now
            let capture = ring.currentCaptureTime()
            var display = PitchDisplayState(level: rms, latencyMilliseconds: 0, bufferSize: bufferSize)

            // Noise-floor-relative level gate. The floor only tracks frames
            // that follow a frame with no current detection, so the player's
            // own note never drags it up; a real note must clear floor +
            // margin, which rejects the quiet pitched room noise (TV, voices,
            // mains hum) that otherwise confirms as phantom notes.
            let levelDb = 20 * log10(max(Double(rms), 0.000_001))
            if !previousFrameConfirmed {
                quietRing[quietRingWrite] = Float(levelDb)
                quietRingWrite = (quietRingWrite + 1) % Self.quietRingCap
                if quietRingFilled < Self.quietRingCap { quietRingFilled += 1 }
                quietFramesSinceRecompute += 1
                if quietFramesSinceRecompute >= 4 {
                    quietFramesSinceRecompute = 0
                    cachedFloorDb = Self.noiseFloor(ring: quietRing, count: quietRingFilled)
                }
            }
            let floorDb = cachedFloorDb

            var hasCurrentDetection = false
            if let result, let mapped = NoteMapper.map(frequency: result.frequency) {
                let candidateMIDI = mapped.midiNote
                let decision = NoteGate.decide(
                    candidateMIDI: candidateMIDI,
                    confidence: result.confidence,
                    lastMIDI: confirmation.lastMIDI,
                    levelDb: levelDb,
                    floorDb: floorDb,
                    sensitivity: sensitivity
                )
                if confirmation.ingest(
                    candidateMIDI: candidateMIDI,
                    frequency: result.frequency,
                    isContinuation: decision.isContinuation,
                    confidencePasses: decision.confidencePasses,
                    levelPasses: decision.levelPasses
                ) {
                    lastFrequency = result.frequency
                    lastDetection = now
                    hasCurrentDetection = true
                    display.confidence = result.confidence
                }
            } else {
                confirmation.clearTransient()
            }
            // A short hold prevents the display from blinking out during the
            // naturally aperiodic final cycles of a decaying guitar note.
            let isWithinHold = lastDetection.map { now - $0 < .milliseconds(180) } ?? false
            if let stable = confirmation.lastMIDI, hasCurrentDetection || isWithinHold {
                let stableFrequency = 440 * pow(2, Double(stable - 69) / 12)
                display.frequency = lastFrequency
                display.note = NoteMapper.map(frequency: stableFrequency)
                if var note = display.note {
                    let rawCents = 1200 * log2(lastFrequency / stableFrequency)
                    // The needle was tracking this raw, per-frame value
                    // directly — every frame's small pitch-estimation
                    // jitter showed up immediately as visible twitch. An
                    // exponential moving average smooths that out; it
                    // resets when the locked note itself changes (rather
                    // than persisting across it) so an actual note change
                    // still reads as an immediate jump, not a slow glide
                    // carrying the previous note's offset into the new one.
                    if smoothedCentsMIDI != stable { smoothedCents = nil; smoothedCentsMIDI = stable }
                    let smoothingFactor = 0.25
                    let smoothed = smoothedCents.map { $0 + smoothingFactor * (rawCents - $0) } ?? rawCents
                    smoothedCents = smoothed
                    note = MappedNote(name: note.name, octave: note.octave, midiNote: note.midiNote, cents: smoothed)
                    display.note = note
                }
            } else {
                confirmation.clearConfirmed()
                lastDetection = nil
                smoothedCents = nil
                smoothedCentsMIDI = nil
            }
            previousFrameConfirmed = hasCurrentDetection
            onUpdate?(display, capture)
        }
    }
}
