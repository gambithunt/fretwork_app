import Foundation

struct ChordDef: Sendable, Equatable {
    let name: String
    let short: String
    let intervals: [Int]
    let degrees: [String]
    let feel: String
}

enum Triads: Sendable {
    static let major = ChordDef(name: "Major", short: "maj", intervals: [0, 4, 7], degrees: ["1", "3", "5"], feel: "Root + major 3rd + perfect 5th. Bright, stable, resolved.")
    static let minor = ChordDef(name: "Minor", short: "min", intervals: [0, 3, 7], degrees: ["1", "b3", "5"], feel: "Root + minor 3rd + perfect 5th. The flattened 3rd makes it dark.")
    static let diminished = ChordDef(name: "Diminished", short: "dim", intervals: [0, 3, 6], degrees: ["1", "b3", "b5"], feel: "Two stacked minor 3rds. Tense, unstable, wants to resolve.")
    static let augmented = ChordDef(name: "Augmented", short: "aug", intervals: [0, 4, 8], degrees: ["1", "3", "#5"], feel: "Two stacked major 3rds. Dreamlike, suspended, ambiguous.")

    static let all: [ChordDef] = [major, minor, diminished, augmented]

    static func triad(short: String) -> ChordDef? {
        all.first { $0.short == short }
    }
}

enum ChordFamilyId: String, Sendable {
    case core
    case sevenths
    case colour
    case extensions
}

struct ChordFormula: Sendable, Equatable {
    let id: String
    let family: ChordFamilyId
    let label: String
    let suffix: String
    let intervals: [Int]
    let degrees: [String]
    let description: String
}

enum ChordFormulas: Sendable {
    /// Chord tones are kept in conventional spelling order, not numeric order:
    /// an add9 ends with its 2 so the degree label and voicing stay aligned.
    static let all: [ChordFormula] = [
        ChordFormula(id: "maj", family: .core, label: "Major", suffix: "", intervals: [0, 4, 7], degrees: ["1", "3", "5"], description: "A bright, stable triad built from the root, major 3rd, and perfect 5th."),
        ChordFormula(id: "min", family: .core, label: "Minor", suffix: "m", intervals: [0, 3, 7], degrees: ["1", "b3", "5"], description: "A darker triad: the minor 3rd gives the chord its character."),
        ChordFormula(id: "power", family: .core, label: "Power", suffix: "5", intervals: [0, 7], degrees: ["1", "5"], description: "Root and perfect 5th only, with no 3rd—so it is neither major nor minor."),
        ChordFormula(id: "7", family: .sevenths, label: "7", suffix: "7", intervals: [0, 4, 7, 10], degrees: ["1", "3", "5", "b7"], description: "A dominant seventh: major triad tension from the added flattened 7th."),
        ChordFormula(id: "maj7", family: .sevenths, label: "maj7", suffix: "maj7", intervals: [0, 4, 7, 11], degrees: ["1", "3", "5", "7"], description: "A major triad with a lush major 7th."),
        ChordFormula(id: "m7", family: .sevenths, label: "m7", suffix: "m7", intervals: [0, 3, 7, 10], degrees: ["1", "b3", "5", "b7"], description: "A minor triad softened by a flattened 7th."),
        ChordFormula(id: "m7b5", family: .sevenths, label: "m7b5", suffix: "m7b5", intervals: [0, 3, 6, 10], degrees: ["1", "b3", "b5", "b7"], description: "Half-diminished: a minor seventh chord with a flattened 5th."),
        ChordFormula(id: "sus2", family: .colour, label: "sus2", suffix: "sus2", intervals: [0, 2, 7], degrees: ["1", "2", "5"], description: "The 2nd replaces the 3rd, leaving the chord open and unresolved."),
        ChordFormula(id: "sus4", family: .colour, label: "sus4", suffix: "sus4", intervals: [0, 5, 7], degrees: ["1", "4", "5"], description: "The 4th replaces the 3rd, creating tension that often resolves to major."),
        ChordFormula(id: "add9", family: .colour, label: "add9", suffix: "add9", intervals: [0, 4, 7, 2], degrees: ["1", "3", "5", "9"], description: "A major triad with an added 9th and no 7th."),
        ChordFormula(id: "6", family: .colour, label: "6", suffix: "6", intervals: [0, 4, 7, 9], degrees: ["1", "3", "5", "6"], description: "A major triad coloured by a warm major 6th."),
        ChordFormula(id: "m6", family: .colour, label: "m6", suffix: "m6", intervals: [0, 3, 7, 9], degrees: ["1", "b3", "5", "6"], description: "A minor triad with a distinctive, warm major 6th."),
        ChordFormula(id: "9", family: .extensions, label: "9", suffix: "9", intervals: [0, 4, 7, 10, 2], degrees: ["1", "3", "5", "b7", "9"], description: "A dominant seventh with an added 9th."),
        ChordFormula(id: "maj9", family: .extensions, label: "maj9", suffix: "maj9", intervals: [0, 4, 7, 11, 2], degrees: ["1", "3", "5", "7", "9"], description: "A major seventh chord extended with a 9th."),
        ChordFormula(id: "m9", family: .extensions, label: "m9", suffix: "m9", intervals: [0, 3, 7, 10, 2], degrees: ["1", "b3", "5", "b7", "9"], description: "A minor seventh chord extended with a 9th."),
        ChordFormula(id: "13", family: .extensions, label: "13", suffix: "13", intervals: [0, 4, 7, 10, 9], degrees: ["1", "3", "5", "b7", "13"], description: "A dominant seventh with a colourful 13th.")
    ]

    static func formula(id: String) -> ChordFormula? {
        all.first { $0.id == id }
    }
}
