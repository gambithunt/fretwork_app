import Foundation

/// A place a note can be played: `string` 0 is the low E, `fret` 0 is open.
struct FretPosition: Hashable, Sendable { let string: Int; let fret: Int }

enum GuitarTuning {
    static let openMIDINotes = [40, 45, 50, 55, 59, 64] // E2 A2 D3 G3 B3 E4
    static let stringNames = ["Low E", "A", "D", "G", "B", "High E"]

    /// Every place `midi` can be played, low string first.
    ///
    /// Pitch alone can't say which of these was actually played — 79% of the
    /// notes in range have more than one, and some have five. Narrowing them
    /// down is `FretPositionResolver`'s job.
    static func positions(forMIDI midi: Int, fretCount: Int = 22) -> [FretPosition] {
        openMIDINotes.enumerated().compactMap { string, open in
            let fret = midi - open
            return (0...fretCount).contains(fret) ? FretPosition(string: string, fret: fret) : nil
        }
    }
}
