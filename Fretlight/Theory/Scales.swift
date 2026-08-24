import Foundation

struct ScaleDef: Sendable, Equatable {
    /// Stable identifier, matching the web app's key for the same scale, so a
    /// persisted selection means the same thing in both.
    let id: String
    let name: String
    /// Semitone offsets from the root, 0 = root.
    let intervals: [Int]
    /// Scale-degree labels, aligned index-for-index with `intervals`.
    let degrees: [String]

    /// Names each degree by advancing one letter per step rather than applying
    /// one global sharp-or-flat preference, which is what preserves theory
    /// spellings like E♯ in F♯ major and D♭ in C Locrian. A pitch class alone
    /// cannot distinguish those from F and C♯; the letter sequence can.
    func spelled(from root: PitchClass) -> [String] {
        let letters = ["C", "D", "E", "F", "G", "A", "B"]
        let naturalValues = [0, 2, 4, 5, 7, 9, 11]
        let rootLetter = String(root.name().prefix(1))
        let rootLetterIndex = letters.firstIndex(of: rootLetter) ?? 0

        return intervals.enumerated().map { index, interval in
            let letterIndex = (rootLetterIndex + index) % letters.count
            let target = root.transposed(by: interval).value
            var offset = (target - naturalValues[letterIndex] + 12) % 12
            // Past a tritone the letter is more cheaply reached by flattening
            // than by stacking sharps, so the accidental flips sign.
            if offset > 6 { offset -= 12 }
            let accidental = offset > 0
                ? String(repeating: "♯", count: offset)
                : String(repeating: "♭", count: -offset)
            return letters[letterIndex] + accidental
        }
    }
}

enum Scales: Sendable {
    static let major = ScaleDef(id: "major", name: "Major", intervals: [0, 2, 4, 5, 7, 9, 11], degrees: ["1", "2", "3", "4", "5", "6", "7"])
    static let naturalMinor = ScaleDef(id: "naturalMinor", name: "Natural minor", intervals: [0, 2, 3, 5, 7, 8, 10], degrees: ["1", "2", "b3", "4", "5", "b6", "b7"])
    static let locrian = ScaleDef(id: "locrian", name: "Locrian", intervals: [0, 1, 3, 5, 6, 8, 10], degrees: ["1", "b2", "b3", "4", "b5", "b6", "b7"])
    static let lydianAugmented = ScaleDef(id: "lydianAugmented", name: "Lydian augmented", intervals: [0, 2, 4, 6, 8, 9, 11], degrees: ["1", "2", "3", "#4", "#5", "6", "7"])
    static let majorPentatonic = ScaleDef(id: "majorPentatonic", name: "Major pentatonic", intervals: [0, 2, 4, 7, 9], degrees: ["1", "2", "3", "5", "6"])
    static let minorPentatonic = ScaleDef(id: "minorPentatonic", name: "Minor pentatonic", intervals: [0, 3, 5, 7, 10], degrees: ["1", "b3", "4", "5", "b7"])

    /// An ordered array, not a dictionary keyed by name. A dictionary has no
    /// stable iteration order, so any UI listing these would shuffle them
    /// between launches, and its string keys are unchecked by the compiler.
    static let all: [ScaleDef] = [major, naturalMinor, locrian, lydianAugmented, majorPentatonic, minorPentatonic]

    static func scale(id: String) -> ScaleDef? {
        all.first { $0.id == id }
    }
}
