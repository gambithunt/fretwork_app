#if DEBUG
import Accelerate
import Darwin
import Foundation

/// Captures one take at a time from the live input, for building the app's
/// note-sample library.
///
/// A fourth consumer of the capture tap with its own `RingBuffer`, following
/// the discipline `CaptureSink` documents for the analysis and chord rings:
/// `RingBuffer` is strictly single-producer/single-consumer, so a second
/// reader on an existing ring corrupts the shared read cursor. The cost on the
/// render thread is one more `write` per block whether or not anyone is
/// recording — the decision to drain lives here, not in the callback.
///
/// Nothing in this type runs on the render thread.
final class SampleRecorder: @unchecked Sendable {
    enum Phase: Sendable {
        /// Draining and reporting level, but not capturing.
        case idle
        /// Waiting for the player to strike the string.
        case armed
        /// Accumulating a take.
        case recording
    }

    /// Raw captured audio. Trimming, normalising and pitch verification belong
    /// to the next phase — this hands back exactly what came off the wire so
    /// those decisions stay reviewable against the original.
    struct Take: Sendable {
        let samples: [Float]
        let sampleRate: Double
        let peak: Float
    }

    /// A take is cut off here regardless of decay. A wound low string can ring
    /// past this, but everything beyond it sits under what the trimmed library
    /// will use, and an uncapped take turns a missed decay into an unbounded
    /// allocation.
    private static let maximumTakeDuration = 6.0
    /// How long the signal must stay back under the onset threshold before a
    /// take is finished. Long enough to ride out the dips between the first
    /// few periods of a low note, which are not the note ending.
    private static let decayHold = 0.35
    /// Multiple of the measured noise floor that counts as a deliberate note.
    /// A DI signal's floor is very low, so this can be generous and still let
    /// a light pick stroke through.
    private static let onsetFactor: Float = 8
    /// Floor under the measured noise floor, so a near-silent DI input cannot
    /// produce a threshold that any stray sample crosses.
    private static let minimumOnsetLevel: Float = 0.002
    private static let chunkFrames = 1024

    private let ring: RingBuffer
    private let queue = DispatchQueue(label: "com.fretlight.sample-recorder", qos: .userInitiated)
    private var running: Int32 = 0

    /// Recorder-queue state. Only `consume` and what it calls touch these.
    private var chunk = [Float](repeating: 0, count: SampleRecorder.chunkFrames)
    private var phase: Phase = .idle
    private var captured: [Float] = []
    private var noiseFloor: Float = 0
    private var onsetThreshold: Float = SampleRecorder.minimumOnsetLevel
    private var quietFrames = 0
    private var sampleRate: Double = 48_000

    /// Set from the main actor before `start`, read on the recorder queue.
    /// Guarded because arming happens while the loop is already draining.
    private let lock = NSLock()
    private var requestedPhase: Phase = .idle

    var onLevel: (@Sendable (Float) -> Void)?
    var onPhase: (@Sendable (Phase) -> Void)?
    var onTake: (@Sendable (Take) -> Void)?

    init(ring: RingBuffer) {
        self.ring = ring
    }

    func start(sampleRate: Double) {
        guard OSAtomicCompareAndSwap32Barrier(0, 1, &running) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.sampleRate = sampleRate
            self.consume()
        }
    }

    func stop() {
        OSAtomicCompareAndSwap32Barrier(1, 0, &running)
    }

    /// Begin waiting for a note. Any take in progress is abandoned — a retake
    /// is a new take, not a continuation.
    func arm() {
        lock.lock(); requestedPhase = .armed; lock.unlock()
    }

    /// Stop waiting, and discard anything captured so far.
    func disarm() {
        lock.lock(); requestedPhase = .idle; lock.unlock()
    }

    private func takeRequestedPhase() -> Phase {
        lock.lock(); defer { lock.unlock() }
        return requestedPhase
    }

    private func consume() {
        var framesSinceNoiseFloorSample = 0

        while OSAtomicAdd32Barrier(0, &running) == 1 {
            // Sleep on every non-productive path. A loop that spins on an
            // empty ring once starved Core Audio's realtime thread badly
            // enough to surface as -10877 from an unrelated layer.
            let didRead = chunk.withUnsafeMutableBufferPointer {
                ring.read(into: $0.baseAddress!, count: Self.chunkFrames)
            }
            guard didRead else {
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }

            let level = chunk.withUnsafeBufferPointer { data -> Float in
                var value: Float = 0
                vDSP_rmsqv(data.baseAddress!, 1, &value, vDSP_Length(data.count))
                return value
            }
            onLevel?(level)

            let requested = takeRequestedPhase()
            if requested == .idle, phase != .idle {
                setPhase(.idle)
                captured.removeAll(keepingCapacity: true)
            } else if requested == .armed, phase == .idle {
                setPhase(.armed)
                captured.removeAll(keepingCapacity: true)
                quietFrames = 0
            }

            switch phase {
            case .idle:
                // The floor is tracked continuously while nothing is being
                // captured, so arming uses a threshold measured against this
                // session's actual noise rather than a constant that assumes
                // a particular interface.
                framesSinceNoiseFloorSample += Self.chunkFrames
                noiseFloor = noiseFloor == 0 ? level : min(noiseFloor, level) + (level - min(noiseFloor, level)) * 0.05
                onsetThreshold = max(noiseFloor * Self.onsetFactor, Self.minimumOnsetLevel)

            case .armed:
                guard level >= onsetThreshold else { continue }
                setPhase(.recording)
                captured.append(contentsOf: chunk)
                quietFrames = 0

            case .recording:
                captured.append(contentsOf: chunk)
                quietFrames = level < onsetThreshold ? quietFrames + Self.chunkFrames : 0
                let decayed = Double(quietFrames) / sampleRate >= Self.decayHold
                let overran = Double(captured.count) / sampleRate >= Self.maximumTakeDuration
                if decayed || overran { finishTake() }
            }
        }
    }

    private func finishTake() {
        var peak: Float = 0
        captured.withUnsafeBufferPointer { data in
            vDSP_maxmgv(data.baseAddress!, 1, &peak, vDSP_Length(data.count))
        }
        let take = Take(samples: captured, sampleRate: sampleRate, peak: peak)
        captured.removeAll(keepingCapacity: true)
        quietFrames = 0
        // Back to idle rather than re-arming: the next take is a deliberate
        // action, so a ringing tail or a knocked string cannot start one.
        lock.lock(); requestedPhase = .idle; lock.unlock()
        setPhase(.idle)
        onTake?(take)
    }

    private func setPhase(_ next: Phase) {
        guard !isSamePhase(phase, next) else { return }
        phase = next
        onPhase?(next)
    }

    private func isSamePhase(_ left: Phase, _ right: Phase) -> Bool {
        switch (left, right) {
        case (.idle, .idle), (.armed, .armed), (.recording, .recording): true
        default: false
        }
    }
}
#endif
