import Foundation

/// Builds the spoken description VoiceOver reads for a board's contents.
///
/// Kept a pure function over plain values (dots, a tuning, a fret count) so it
/// has no dependency on the view that hosts it and can be exercised directly
/// from a test, the same way `accessibilityDescription` in `FretboardView`
/// already builds its string by hand rather than through a view modifier.
enum FretboardAccessibility {
    /// Above this many dots, VoiceOver switches from naming each one to
    /// summarizing the board. A full scale pattern can put over a hundred
    /// dots on the neck at once, and nobody navigating by voice wants each
    /// one read individually — they want the shape: how many, where it
    /// starts and ends. Eight is small enough that every dot in, say, a
    /// single-octave arpeggio still gets named outright.
    static let enumerationLimit = 8

    static func describe(dots: [FretboardDot], tuning: Tuning, fretCount: Int) -> String {
        guard !dots.isEmpty else {
            return "No notes marked on the \(fretCount)-fret fretboard."
        }

        let ordered = dots.sorted { lhs, rhs in
            if lhs.position.string != rhs.position.string {
                return lhs.position.string < rhs.position.string
            }
            return lhs.position.fret < rhs.position.fret
        }

        return ordered.count > enumerationLimit
            ? summary(of: ordered, tuning: tuning)
            : enumeration(of: ordered, tuning: tuning)
    }

    /// A stable name for a string index even if it somehow falls outside the
    /// tuning's own list — a mismatched string count between caller and
    /// tuning shouldn't crash a description, just degrade it.
    private static func stringName(_ string: Int, in tuning: Tuning) -> String {
        let names = tuning.stringNames
        return names.indices.contains(string) ? names[string] : "string \(string)"
    }

    private static func fretPhrase(_ fret: Int) -> String {
        fret == 0 ? "open" : "fret \(fret)"
    }

    /// One clause per dot, in low-string-to-high, low-fret-to-high order — the
    /// order a player's eye would actually sweep the neck in.
    private static func enumeration(of dots: [FretboardDot], tuning: Tuning) -> String {
        let clauses = dots.map { dot -> String in
            let role = dot.role.map { " (\($0))" } ?? ""
            return "\(stringName(dot.position.string, in: tuning)) string, \(fretPhrase(dot.position.fret))\(role)"
        }
        let noun = dots.count == 1 ? "note" : "notes"
        return "\(dots.count) \(noun) marked: \(clauses.joined(separator: "; "))."
    }

    /// A large board is described by its extent rather than its members: how
    /// many dots, and the string and fret span they cover.
    private static func summary(of dots: [FretboardDot], tuning: Tuning) -> String {
        let strings = dots.map(\.position.string)
        let frets = dots.map(\.position.fret)
        let lowestString = stringName(strings.min() ?? 0, in: tuning)
        let highestString = stringName(strings.max() ?? 0, in: tuning)
        let lowestFret = frets.min() ?? 0
        let highestFret = frets.max() ?? 0
        let fretSpan = lowestFret == 0 ? "open through fret \(highestFret)" : "fret \(lowestFret) through fret \(highestFret)"
        return "\(dots.count) notes marked across the fretboard, from the \(lowestString) string to the \(highestString) string, \(fretSpan)."
    }
}
