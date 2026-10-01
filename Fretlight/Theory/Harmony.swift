import Foundation

struct DiatonicChord: Sendable {
    let degree: Int
    let roman: String
    let quality: String
    let name: String
    let root: PitchClass
    let pitchClasses: [PitchClass]
    let intervals: [Int]
    let degrees: [String]
}

enum Harmony: Sendable {
    static let majorQualities = ["maj", "min", "min", "maj", "maj", "min", "dim"]
    static let minorQualities = ["min", "dim", "maj", "min", "min", "maj", "maj"]
    static let majorRomans = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
    static let minorRomans = ["i", "ii°", "III", "iv", "v", "VI", "VII"]
    /// Clockwise from C, each step a perfect fifth up. Derived from
    /// `Keys.circleOfFifths` so the ring's order and its spellings cannot drift
    /// apart.
    static let circleOfFifths = Keys.circleOfFifths.map(\.tonic)

    static func diatonicChords(root: PitchClass, major: Bool) -> [DiatonicChord] {
        let scale = major ? Scales.major : Scales.naturalMinor
        let qualities = major ? majorQualities : minorQualities
        let romans = major ? majorRomans : minorRomans
        let notes = scale.intervals.map { root.transposed(by: $0) }
        return notes.indices.map { index in
            let chordRoot = notes[index]
            let third = notes[(index + 2) % 7]
            let fifth = notes[(index + 4) % 7]
            let thirdInterval = (third.value - chordRoot.value + 12) % 12
            let fifthInterval = (fifth.value - chordRoot.value + 12) % 12
            let quality = qualities[index]
            return DiatonicChord(degree: index, roman: romans[index], quality: quality, name: chordRoot.name() + suffix(for: quality), root: chordRoot, pitchClasses: [chordRoot, third, fifth], intervals: [0, thirdInterval, fifthInterval], degrees: triadDegrees(third: thirdInterval, fifth: fifthInterval))
        }
    }

    static func keyScalePitchClasses(root: PitchClass, major: Bool) -> [PitchClass] {
        (major ? Scales.major : Scales.naturalMinor).intervals.map { root.transposed(by: $0) }
    }

    static func keyPentatonicPitchClasses(root: PitchClass, major: Bool) -> [PitchClass] {
        (major ? Scales.majorPentatonic : Scales.minorPentatonic).intervals.map { root.transposed(by: $0) }
    }

    private static func suffix(for quality: String) -> String {
        switch quality { case "min": "m"; case "dim": "°"; case "aug": "+"; default: "" }
    }

    private static func triadDegrees(third: Int, fifth: Int) -> [String] {
        ["1", third == 3 ? "b3" : "3", fifth == 6 ? "b5" : fifth == 8 ? "#5" : "5"]
    }
}
