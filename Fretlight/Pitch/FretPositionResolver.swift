import Foundation

/// A candidate position for the current note, ranked against the alternatives.
struct RankedPosition: Hashable, Sendable, Identifiable {
    let position: FretPosition
    /// 0 is the resolver's pick; the rest are alternates, most plausible first.
    let rank: Int
    var isPrimary: Bool { rank == 0 }
    var id: FretPosition { position }
}

/// Decides which of a pitch's possible fretboard positions is actually being
/// played, by tracking where the fretting hand appears to be.
///
/// The prior is hand travel: a player who just fretted the 12th fret is far
/// more likely to play the next note near the 12th than to jump to the 3rd for
/// the same pitch. That alone resolves most ambiguity, because two positions
/// for one pitch are never adjacent — in standard tuning the closest pair is
/// always 4 frets apart, and across every tuning offered it never closes below
/// 2 (DADGAD, whose G and A strings sit a whole tone apart rather than the
/// usual fourth). So the estimate only has to be accurate to a couple of frets
/// to pick correctly.
///
/// Deliberately causal. Scoring a whole phrase at once (Viterbi over the note
/// sequence) would be more accurate, but it can only score a note once the
/// notes *after* it have arrived, and a live fretboard display can't wait for
/// them. So the estimate is carried forward and updated note by note, which
/// costs accuracy in exactly one place: a sudden jump to a new position is
/// guessed from stale information and takes a note or two to recover. That
/// case — being right about the first note in a new position — is the gap a
/// camera watching the hand would fill.
@MainActor
final class FretPositionResolver {
    /// Believed hand position, in frets. Smoothed rather than snapped to the
    /// last note, so a single misread note can't drag it across the neck.
    private var anchorFret: Double?
    private var anchorString: Int?
    private var lastPlayed: ContinuousClock.Instant?

    /// Charged to an open string once the hand's position is known. An open
    /// string needs no particular hand position, so travel can't be charged
    /// against it — but it shouldn't automatically beat a fretted note sitting
    /// directly under the hand either.
    private let openStringCost = 2.5
    /// Travel beyond which the hand has plainly moved somewhere new, so the
    /// estimate snaps to it rather than easing toward it.
    private let jumpThreshold = 5.0
    private let smoothing = 0.55
    /// Reaching across strings barely moves the hand, so it only breaks ties.
    private let stringWeight = 0.15
    /// After this long without a fretted note, the hand could be anywhere.
    private let memorySpan = Duration.seconds(2.5)

    func resolve(midiNote: Int, fretCount: Int = 22, tuning: Tuning = Tunings.standard, now: ContinuousClock.Instant = .now) -> [RankedPosition] {
        let candidates = GuitarTuning.positions(forMIDI: midiNote, fretCount: fretCount, tuning: tuning)
        guard !candidates.isEmpty else { return [] }
        if let lastPlayed, now - lastPlayed > memorySpan { forget() }
        var scored: [Scored] = candidates.map { Scored(position: $0, cost: cost(of: $0)) }
        scored.sort { left, right in
            left.cost == right.cost ? left.position.fret < right.position.fret : left.cost < right.cost
        }
        guard let chosen = scored.first else { return [] }
        remember(chosen.position, cost: chosen.cost, at: now)
        return scored.enumerated().map { RankedPosition(position: $1.position, rank: $0) }
    }

    private struct Scored {
        let position: FretPosition
        let cost: Double
    }

    func reset() {
        forget()
        lastPlayed = nil
    }

    private func cost(of position: FretPosition) -> Double {
        guard let anchorFret else {
            // Nothing known about the hand yet, so prefer the lowest fret.
            // That makes an open string the natural opening guess, which is
            // what a player reaching for a cold note most often uses.
            return Double(position.fret)
        }
        guard position.fret > 0 else { return openStringCost }
        var value = abs(Double(position.fret) - anchorFret)
        if let anchorString { value += abs(Double(position.string - anchorString)) * stringWeight }
        return value
    }

    private func remember(_ position: FretPosition, cost: Double, at now: ContinuousClock.Instant) {
        lastPlayed = now
        // An open string sounds whatever the fretting hand happens to be
        // doing, so it carries no information about where that hand is and
        // must leave the estimate untouched.
        guard position.fret > 0 else { return }
        anchorString = position.string
        let fret = Double(position.fret)
        if let current = anchorFret, cost <= jumpThreshold {
            anchorFret = current + (fret - current) * smoothing
        } else {
            anchorFret = fret
        }
    }

    private func forget() {
        anchorFret = nil
        anchorString = nil
    }
}
