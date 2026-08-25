import Foundation

/// One note the player has placed on the board.
struct DiscoveredNote: Sendable {
    let pitchClass: PitchClass
    let midiNote: Int
    let string: Int
}

enum ChordDiscoveryStatus: Sendable {
    case empty
    case insufficient
    case partial
    case match
    case unknown
}

enum ChordInversion: String, Sendable {
    case first = "1st inversion"
    case second = "2nd inversion"
    case third = "3rd inversion"

    /// `degreeIndex` is where the bass note falls among the formula's tones.
    /// A third inversion needs a fourth tone to be inverted onto, so a triad
    /// stops at second however low its fifth is voiced.
    init?(degreeIndex: Int, toneCount: Int) {
        switch degreeIndex {
        case 1: self = .first
        case 2: self = .second
        case 3 where toneCount >= 4: self = .third
        default: return nil
        }
    }
}

struct DiscoveredChordMatch: Sendable {
    let root: PitchClass
    let quality: String
    /// Carries a slash bass when the voicing is playable and inverted.
    let symbol: String
    let baseSymbol: String
    let degrees: [String]
    let inversion: ChordInversion?
}

struct ChordDiscoveryResult: Sendable {
    let status: ChordDiscoveryStatus
    let uniquePitchClasses: [PitchClass]
    let playableVoicing: Bool
    let primary: DiscoveredChordMatch?
    let matches: [DiscoveredChordMatch]
    let alternatives: [DiscoveredChordMatch]
    let message: String
}

/// Names the chord a set of placed notes forms.
///
/// Not to be confused with `ChordDetector`, which answers a different question
/// from a different signal: what is being strummed, inferred from audio chroma
/// with a confidence score. This one works from exact positions and either
/// matches a pitch set exactly or says it cannot.
enum ChordDiscovery: Sendable {
    struct Formula: Sendable {
        let quality: String
        let suffix: String
        let intervals: [Int]
        let degrees: [String]
        /// Lower wins when two formulas describe the same pitch set — and they
        /// do: A minor 7 and C6 are the same four notes, as are C minor 6 and
        /// A half-diminished 7, and a diminished 7 is one set with four equally
        /// valid roots. Priority only settles cases the bass note leaves open.
        let priority: Int
    }

    /// Deliberately separate from `ChordFormulas` in `Chords.swift`. That table
    /// backs the curated voicing library and holds what a player looks up; this
    /// one has to recognise an arbitrary pitch set, so it carries `dim7` and
    /// `m(maj7)`, drops the extensions, and stacks `add9` as `[0, 2, 4, 7]`
    /// rather than the library's voicing order. Unifying them would break one
    /// job or the other.
    static let formulas = [
        Formula(quality: "Major", suffix: "", intervals: [0, 4, 7], degrees: ["1", "3", "5"], priority: 0),
        Formula(quality: "Minor", suffix: "m", intervals: [0, 3, 7], degrees: ["1", "b3", "5"], priority: 1),
        Formula(quality: "Diminished", suffix: "dim", intervals: [0, 3, 6], degrees: ["1", "b3", "b5"], priority: 2),
        Formula(quality: "Augmented", suffix: "aug", intervals: [0, 4, 8], degrees: ["1", "3", "#5"], priority: 3),
        Formula(quality: "Suspended 2", suffix: "sus2", intervals: [0, 2, 7], degrees: ["1", "2", "5"], priority: 4),
        Formula(quality: "Suspended 4", suffix: "sus4", intervals: [0, 5, 7], degrees: ["1", "4", "5"], priority: 5),
        Formula(quality: "Major 7", suffix: "maj7", intervals: [0, 4, 7, 11], degrees: ["1", "3", "5", "7"], priority: 6),
        Formula(quality: "Dominant 7", suffix: "7", intervals: [0, 4, 7, 10], degrees: ["1", "3", "5", "b7"], priority: 7),
        Formula(quality: "Minor 7", suffix: "m7", intervals: [0, 3, 7, 10], degrees: ["1", "b3", "5", "b7"], priority: 8),
        Formula(quality: "Minor-major 7", suffix: "m(maj7)", intervals: [0, 3, 7, 11], degrees: ["1", "b3", "5", "7"], priority: 9),
        Formula(quality: "Diminished 7", suffix: "dim7", intervals: [0, 3, 6, 9], degrees: ["1", "b3", "b5", "bb7"], priority: 10),
        Formula(quality: "Half-diminished 7", suffix: "m7b5", intervals: [0, 3, 6, 10], degrees: ["1", "b3", "b5", "b7"], priority: 11),
        Formula(quality: "Major 6", suffix: "6", intervals: [0, 4, 7, 9], degrees: ["1", "3", "5", "6"], priority: 12),
        Formula(quality: "Minor 6", suffix: "m6", intervals: [0, 3, 7, 9], degrees: ["1", "b3", "5", "6"], priority: 13),
        Formula(quality: "Add 9", suffix: "add9", intervals: [0, 2, 4, 7], degrees: ["1", "2", "3", "5"], priority: 14)
    ]

    static func discover(_ notes: [DiscoveredNote]) -> ChordDiscoveryResult {
        let pitchClasses = Set(notes.map(\.pitchClass)).sorted { $0.value < $1.value }
        // A real voicing sounds at most one note per string, and a guitar has
        // six. Anything else is a pitch set the player has drawn rather than a
        // shape they could hold, which limits what can honestly be said about
        // it — a bass note nobody can actually put lowest names no inversion.
        let playable = notes.count <= 6 && Set(notes.map(\.string)).count == notes.count

        if pitchClasses.isEmpty {
            return result(.empty, pitchClasses, playable, "Add notes to discover a chord.")
        }
        if pitchClasses.count == 1 {
            return result(.insufficient, pitchClasses, playable, "Add at least 2 more different notes.")
        }

        let bass = notes.min { $0.midiNote < $1.midiNote }?.pitchClass

        if pitchClasses.count == 2 {
            return twoNoteResult(pitchClasses, playable: playable)
        }

        var candidates: [(match: DiscoveredChordMatch, priority: Int, bassIsRoot: Bool)] = []
        for formula in formulas {
            for root in PitchClass.chromatic
            where Set(formula.intervals.map { root.transposed(by: $0) }) == Set(pitchClasses) {
                let match = makeMatch(root: root, formula: formula, bass: bass, playable: playable)
                candidates.append((match, formula.priority, bass == root))
            }
        }

        guard !candidates.isEmpty else {
            return result(.unknown, pitchClasses, playable, "No common exact chord match.")
        }

        candidates.sort {
            if $0.bassIsRoot != $1.bassIsRoot { return $0.bassIsRoot }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.match.root.value < $1.match.root.value
        }

        let matches = candidates.map(\.match)
        let primary = matches[0]
        let context: String
        if !playable {
            context = " This is a pitch-set match rather than a playable voicing."
        } else if let inversion = primary.inversion, let bass {
            context = " \(bass.name()) is lowest, so this is \(inversion.rawValue)."
        } else {
            context = ""
        }

        return ChordDiscoveryResult(
            status: .match,
            uniquePitchClasses: pitchClasses,
            playableVoicing: playable,
            primary: primary,
            matches: matches,
            alternatives: Array(matches.dropFirst()),
            message: "\(pitchClasses.map { $0.name() }.joined(separator: "–")) forms \(primary.degrees.joined(separator: "–")).\(context)"
        )
    }

    private static func twoNoteResult(_ pitchClasses: [PitchClass], playable: Bool) -> ChordDiscoveryResult {
        // Only one of a pair a fifth apart can be the root of that fifth, so
        // there is never a second candidate for the bass note to choose
        // between — the source's tie-break here has nothing to break.
        let root = pitchClasses.first { Set([$0, $0.transposed(by: 7)]) == Set(pitchClasses) }
        guard let root else {
            return result(.insufficient, pitchClasses, playable, "Add another different note to identify a chord.")
        }
        let symbol = root.name() + "5"
        let match = DiscoveredChordMatch(
            root: root,
            quality: "Power chord",
            symbol: symbol,
            baseSymbol: symbol,
            degrees: ["1", "5"],
            inversion: nil
        )
        return ChordDiscoveryResult(
            status: .partial,
            uniquePitchClasses: pitchClasses,
            playableVoicing: playable,
            primary: match,
            matches: [match],
            alternatives: [],
            message: "\(symbol) is possible, but there is no 3rd to establish major or minor."
        )
    }

    private static func makeMatch(root: PitchClass, formula: Formula, bass: PitchClass?, playable: Bool) -> DiscoveredChordMatch {
        let baseSymbol = root.name() + formula.suffix
        guard playable, let bass, bass != root else {
            return DiscoveredChordMatch(
                root: root,
                quality: formula.quality,
                symbol: baseSymbol,
                baseSymbol: baseSymbol,
                degrees: formula.degrees,
                inversion: nil
            )
        }
        let bassInterval = (bass.value - root.value + 12) % 12
        let inversion = formula.intervals.firstIndex(of: bassInterval)
            .flatMap { ChordInversion(degreeIndex: $0, toneCount: formula.intervals.count) }
        return DiscoveredChordMatch(
            root: root,
            quality: formula.quality,
            symbol: baseSymbol + "/" + bass.name(),
            baseSymbol: baseSymbol,
            degrees: formula.degrees,
            inversion: inversion
        )
    }

    private static func result(_ status: ChordDiscoveryStatus, _ pitchClasses: [PitchClass], _ playable: Bool, _ message: String) -> ChordDiscoveryResult {
        ChordDiscoveryResult(
            status: status,
            uniquePitchClasses: pitchClasses,
            playableVoicing: playable,
            primary: nil,
            matches: [],
            alternatives: [],
            message: message
        )
    }
}
