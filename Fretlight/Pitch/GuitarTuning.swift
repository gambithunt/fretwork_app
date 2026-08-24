import Foundation

/// A place a note can be played: `string` 0 is the low E, `fret` 0 is open.
struct FretPosition: Hashable, Sendable { let string: Int; let fret: Int }

enum GuitarTuning {
    /// The listening screen is still standard-tuning-only, so it reads its
    /// string labels from here rather than threading a tuning through every
    /// view. It gains one when the tuning picker lands.
    static var stringNames: [String] { Tunings.standard.stringNames }

    /// Every place `midi` can be played, low string first.
    ///
    /// Pitch alone can't say which of these was actually played — 79% of the
    /// notes in range have more than one, and some have five. Narrowing them
    /// down is `FretPositionResolver`'s job.
    static func positions(forMIDI midi: Int, fretCount: Int = 22, tuning: Tuning = Tunings.standard) -> [FretPosition] {
        tuning.openMIDINotes.enumerated().compactMap { string, open in
            let fret = midi - open
            return (0...fretCount).contains(fret) ? FretPosition(string: string, fret: fret) : nil
        }
    }
}
