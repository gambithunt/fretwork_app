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
    enum Phase: Sendable, Equatable {
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
    /// How long the signal must stay under the *decay* threshold before a
    /// take is finished. Long enough to ride out the dips between the first
    /// few periods of a low note, which are not the note ending.
    private static let decayHold = 0.35

    /// Where a note counts as over, as a fraction of that take's own peak —
    /// roughly -34 dB below it.
    ///
    /// Onset and decay cannot share a threshold. A plucked string is loudest
    /// at the attack and falls away from there, so a level high enough not to
    /// trigger on room noise is also a level the note drops back under within
    /// about a second. Sharing one number ended every take just as the string
    /// got going. Onset is measured against the noise floor because it asks
    /// "did something start"; decay is measured against the take's own peak
    /// because it asks "has this particular note finished".
    private static let decayFractionOfPeak: Float = 0.02
    /// How fast the recent-peak readout falls away, per chunk — roughly a
    /// one-second memory, long enough to still be on screen after a pluck.
    private static let recentPeakDecay: Float = 0.97

    /// How fast the noise floor may climb, per chunk — about 2.4% a second.
    ///
    /// The floor snaps *down* to any quieter moment instantly but recovers
    /// upward only at this rate. It has to be a floor, not an average. The
    /// first version crept 5% toward the current level on every chunk, which
    /// at ~47 chunks a second meant a couple of seconds of playing while
    /// unarmed taught it to treat the guitar itself as noise: the gate rose
    /// above the signal and no note could ever trigger again. Recovering
    /// slowly still follows a genuine rise in room noise, while a played note
    /// cannot drag it up.
    private static let noiseFloorRecovery: Float = 1.0005

    /// Multiple of the measured noise floor that counts as a deliberate note.
    ///
    /// Was 8, chosen against synthesised tones that go from digital silence to
    /// full amplitude in one sample. A real DI has a noise floor that is not
    /// silence and a pick stroke that ramps, so 8x the floor sat above where
    /// a normally-played note actually starts. 3x still clears room tone and
    /// handling noise comfortably.
    private static let onsetFactor: Float = 3
    /// Floor under the measured noise floor, so a near-silent DI input cannot
    /// produce a threshold that any stray sample crosses. This is an RMS over
    /// 1024 frames, not a peak, so it sits well below what it looks like.
    private static let minimumOnsetLevel: Float = 0.0008
    private static let chunkFrames = 1024

    private let ring: RingBuffer
    private let queue = DispatchQueue(label: "com.fretlight.sample-recorder", qos: .userInitiated)
    private var running: Int32 = 0

    /// Recorder-queue state. Only `consume` and what it calls touch these.
    private var chunk = [Float](repeating: 0, count: SampleRecorder.chunkFrames)
    private var phase: Phase = .idle
    private var captured: [Float] = []
    private var noiseFloor: Float = 0
    /// Tracked separately rather than using `noiseFloor == 0` as the sentinel:
    /// against a digitally silent input the floor legitimately *is* zero, so
    /// the sentinel never cleared and every chunk re-seeded the floor from
    /// whatever had just arrived — including the note itself.
    private var hasNoiseFloor = false
    private var recentPeak: Float = 0
    private var onsetThreshold: Float = SampleRecorder.minimumOnsetLevel
    private var quietFrames = 0
    /// The loudest the current take has been, which is what its decay is
    /// judged against.
    private var takePeak: Float = 0
    private var sampleRate: Double = 48_000

    /// Set from the main actor before `start`, read on the recorder queue.
    /// Guarded because arming happens while the loop is already draining.
    private let lock = NSLock()
    private var requestedPhase: Phase = .idle

    /// What the recorder is hearing, all measured in the same pass on its own
    /// queue. Reported together rather than exposed separately because a UI
    /// comparing a fresh level against a stale threshold would be lying about
    /// whether a note would trigger.
    struct LevelReading: Sendable {
        let level: Float
        /// The threshold currently in force: onset while waiting, decay while
        /// recording.
        let gate: Float
        /// The measured input noise floor. On screen because a signal that
        /// barely clears its own noise is an input problem no threshold can
        /// fix, and that is invisible unless the floor is shown.
        let noiseFloor: Float
        /// The loudest chunk in roughly the last second.
        ///
        /// `level` is an RMS over 21 ms, so on a decaying string it reads the
        /// average of whatever window it lands in — which on a pluck is
        /// mostly the tail, not the attack. The gate is crossed or missed at
        /// the attack, so a live RMS alone cannot tell you whether a note
        /// would have triggered. This can.
        let recentPeak: Float
    }

    var onLevel: (@Sendable (LevelReading) -> Void)?
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

    /// Whether the drain loop is actually going. Enabling the recorder is not
    /// the same as running it: if the audio engine never started there is no
    /// sample rate to start it with, and the difference is otherwise
    /// completely silent — the window looks armed and simply never hears
    /// anything.
    var isRunning: Bool {
        OSAtomicAdd32Barrier(0, &running) == 1
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
            // While recording, the number worth showing is the one actually
            // in force — the decay gate, not the onset gate that has already
            // done its job.
            recentPeak = max(level, recentPeak * Self.recentPeakDecay)
            let activeThreshold = phase == .recording ? decayThreshold() : onsetThreshold
            onLevel?(LevelReading(level: level, gate: activeThreshold, noiseFloor: noiseFloor, recentPeak: recentPeak))

            let requested = takeRequestedPhase()
            if requested == .idle, phase != .idle {
                setPhase(.idle)
                captured.removeAll(keepingCapacity: true)
            } else if requested == .armed, phase == .idle {
                setPhase(.armed)
                captured.removeAll(keepingCapacity: true)
                quietFrames = 0
                takePeak = 0
            }

            // Tracked whenever a take is not in progress — including while
            // armed and waiting, which is usually the quietest the input ever
            // gets — so arming uses a threshold measured against this
            // session's actual noise rather than a constant that assumes a
            // particular interface.
            if phase != .recording {
                noiseFloor = hasNoiseFloor ? min(level, noiseFloor * Self.noiseFloorRecovery) : level
                hasNoiseFloor = true
                onsetThreshold = max(noiseFloor * Self.onsetFactor, Self.minimumOnsetLevel)
            }

            switch phase {
            case .idle:
                break

            case .armed:
                guard level >= onsetThreshold else { continue }
                setPhase(.recording)
                captured.append(contentsOf: chunk)
                quietFrames = 0
                takePeak = level

            case .recording:
                captured.append(contentsOf: chunk)
                takePeak = max(takePeak, level)
                quietFrames = level < decayThreshold() ? quietFrames + Self.chunkFrames : 0
                let decayed = Double(quietFrames) / sampleRate >= Self.decayHold
                let overran = Double(captured.count) / sampleRate >= Self.maximumTakeDuration
                if decayed || overran { finishTake() }
            }
        }
    }

    /// Never below the noise floor: a take must not run on recording room
    /// tone after the string has genuinely stopped.
    private func decayThreshold() -> Float {
        max(noiseFloor * 1.5, takePeak * Self.decayFractionOfPeak, Self.minimumOnsetLevel)
    }

    private func finishTake() {
        var peak: Float = 0
        captured.withUnsafeBufferPointer { data in
            vDSP_maxmgv(data.baseAddress!, 1, &peak, vDSP_Length(data.count))
        }
        let take = Take(samples: captured, sampleRate: sampleRate, peak: peak)
        captured.removeAll(keepingCapacity: true)
        quietFrames = 0
        takePeak = 0
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
