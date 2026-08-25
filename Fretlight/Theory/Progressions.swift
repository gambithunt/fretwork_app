import Foundation

/// Which of a key's two modes something is written for. Deliberately not named
/// `HarmonyMode` — `TriadVoicings` already uses that name for a different axis
/// entirely (triads versus double-stops), and the web app's habit of reusing
/// one name for both is worth not importing.
enum KeyMode: Sendable {
    case major
    case minor

    init(major: Bool) {
        self = major ? .major : .minor
    }
}

enum ProgressionID: String, Sendable {
    case pop1564 = "pop-1564"
    case iiVI = "ii-v-i"
}

struct Progression: Sendable {
    let id: ProgressionID
    let name: String
    /// Zero-based scale degrees, indexing the key's diatonic chords.
    let degrees: [Int]
    let applicableModes: Set<KeyMode>
    let beatsPerChord: Int
}

enum Progressions: Sendable {
    static let all = [
        Progression(id: .pop1564, name: "I–V–vi–IV", degrees: [0, 4, 5, 3], applicableModes: [.major], beatsPerChord: 4),
        Progression(id: .iiVI, name: "ii–V–I", degrees: [1, 4, 0], applicableModes: [.major], beatsPerChord: 4)
    ]

    static func progression(id: ProgressionID) -> Progression {
        all.first { $0.id == id } ?? all[0]
    }

    /// Empty, rather than transposed, for a mode the progression was not
    /// written for: a ii–V–I borrowed into minor is a different progression,
    /// not this one relabelled.
    static func resolve(root: PitchClass, major: Bool, progressionID: ProgressionID) -> [DiatonicChord] {
        let progression = progression(id: progressionID)
        guard progression.applicableModes.contains(KeyMode(major: major)) else { return [] }
        let chords = Harmony.diatonicChords(root: root, major: major)
        return progression.degrees.compactMap { chords.indices.contains($0) ? chords[$0] : nil }
    }
}
