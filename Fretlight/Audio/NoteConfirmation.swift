import Foundation

/// Pure note-confirmation state machine behind `AudioAnalysisWorker`'s consume
/// loop, kept side-effect free so the leap-vs-blip rules can be pinned by unit
/// tests without standing up the ring, queue and wall-clock throttling.
///
/// The worker feeds one candidate per published frame and treats a `true`
/// return as "this frame carries a current detection, so move the frequency
/// readout to this frame's estimate". The name itself lives in `lastMIDI`.
///
/// Two rules coexist:
///
/// - **Median.** While the candidate continues the confirmed note (within
///   ±1 semitone) *or* leaps to a different pitch (≥2 semitones), `lastMIDI`
///   only moves when the median of the last five candidate MIDIs agrees —
///   ±1-semitone jitter never oscillates the displayed name, and an isolated
///   1–2 frame octave/harmonic spike never switches it. A leap therefore
///   shows the new frequency immediately and the new name three publishes
///   later, when the median majority lands.
/// - **New-note stability gate.** A brand-new note (no confirmed note yet)
///   commits once two of the last three confidence-gated candidate frequencies
///   agree within ±20¢; the level gate fires once on the confirming frame.
struct NoteConfirmation: Sendable {
    /// The currently confirmed MIDI note, if any.
    private(set) var lastMIDI: Int?

    /// Last five candidate MIDIs feeding the median.
    private var history: [Int] = []

    /// Last three candidate frequencies feeding the new-note stability gate.
    private var pendingFrequencies: [Double] = []

    /// Two candidates agree within this many cents for a new note to confirm.
    static let stabilityCents = 20.0

    mutating func reset() {
        lastMIDI = nil
        history.removeAll(keepingCapacity: true)
        pendingFrequencies.removeAll(keepingCapacity: true)
    }

    /// Drops per-candidate state when no candidate exists this frame. The
    /// confirmed `lastMIDI` is deliberately preserved so the worker's short
    /// display hold can keep showing it during a gap.
    mutating func clearTransient() {
        history.removeAll(keepingCapacity: true)
        pendingFrequencies.removeAll(keepingCapacity: true)
    }

    /// Drops the confirmed note once the worker's display hold has expired.
    mutating func clearConfirmed() {
        lastMIDI = nil
    }

    /// True when any two of the candidate frequencies agree within `cents`.
    static func anyPairWithinCents(_ frequencies: [Double], cents: Double) -> Bool {
        guard frequencies.count >= 2 else { return false }
        let sorted = frequencies.sorted()
        for index in 0..<(sorted.count - 1) where abs(1200 * log2(sorted[index + 1] / sorted[index])) <= cents {
            return true
        }
        return false
    }

    /// Feeds one published frame's candidate. Returns true when this frame
    /// carries a current detection, which is also the frame on which the
    /// worker moves its frequency readout to this frame's estimate.
    mutating func ingest(
        candidateMIDI: Int,
        frequency: Double,
        isContinuation: Bool,
        confidencePasses: Bool,
        levelPasses: Bool
    ) -> Bool {
        if isContinuation {
            // A confirmed note continuing: held at a relaxed confidence floor
            // and level-exempt so a decaying note doesn't drop. Any half-formed
            // stability run for a different pitch is abandoned.
            pendingFrequencies.removeAll(keepingCapacity: true)
            guard confidencePasses else {
                history.removeAll(keepingCapacity: true)
                return false
            }
            history.append(candidateMIDI)
            if history.count > 5 { history.removeFirst() }
            let median = history.sorted()[history.count / 2]
            if let last = lastMIDI {
                if abs(median - last) <= 1 || history.filter({ $0 == median }).count >= 3 {
                    lastMIDI = median
                }
            } else {
                lastMIDI = median
            }
            return true
        }

        guard confidencePasses else {
            history.removeAll(keepingCapacity: true)
            pendingFrequencies.removeAll(keepingCapacity: true)
            return false
        }

        if lastMIDI != nil {
            // Changed note (a leap of ≥2 semitones). The 3-of-5 median is the
            // octave/harmonic-spike guard: the name commits only after three of
            // the last five candidates agree on the new pitch, so a 1–2 frame
            // blip never flashes on screen. The frequency readout still moves
            // on every level-passing changed frame, keeping it as fast as
            // before.
            guard levelPasses else {
                history.removeAll(keepingCapacity: true)
                return false
            }
            history.append(candidateMIDI)
            if history.count > 5 { history.removeFirst() }
            let median = history.sorted()[history.count / 2]
            if abs(median - lastMIDI!) <= 1 || history.filter({ $0 == median }).count >= 3 {
                lastMIDI = median
            }
            return true
        }

        // New note: stability-gated. Confidence-gated but not level-gated
        // candidates accumulate so a weak note still confirms; the level gate
        // fires once on the confirming frame.
        pendingFrequencies.append(frequency)
        if pendingFrequencies.count > 3 { pendingFrequencies.removeFirst() }
        guard levelPasses, Self.anyPairWithinCents(pendingFrequencies, cents: Self.stabilityCents) else {
            return false
        }

        // Commit: the median restarts from the confirmed pitch so the first
        // continuation frame cannot drag the name back to the note the leap
        // just left.
        history.removeAll(keepingCapacity: true)
        history.append(candidateMIDI)
        lastMIDI = candidateMIDI
        pendingFrequencies.removeAll(keepingCapacity: true)
        return true
    }
}
