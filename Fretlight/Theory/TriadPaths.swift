import Foundation

enum TriadPathStringSet: String, CaseIterable, Sendable {
    case ead = "E–A–D"
    case adg = "A–D–G"
    case dgb = "D–G–B"
    case gbe = "G–B–E"
}

struct TriadPathStep: Sendable {
    let id: String
    let chord: DiatonicChord
    let voicing: CompactVoicing
}

enum TriadPaths: Sendable {
    static let stringSets: [TriadPathStringSet] = [.ead, .adg, .dgb, .gbe]

    static func stringIndices(for stringSet: TriadPathStringSet) -> [Int] {
        switch stringSet {
        case .ead: [0, 1, 2]
        case .adg: [1, 2, 3]
        case .dgb: [2, 3, 4]
        case .gbe: [3, 4, 5]
        }
    }

    /// Every diatonic triad voicing on one three-string set, ordered so that
    /// walking the list walks up the neck. The set is never left — staying on
    /// three adjacent strings while the harmony moves is the whole exercise.
    static func diatonicPath(keyRoot: PitchClass, major: Bool, stringSet: TriadPathStringSet) -> [TriadPathStep] {
        let target = stringIndices(for: stringSet)
        return Harmony.diatonicChords(root: keyRoot, major: major).flatMap { chord in
            guard let triad = Triads.triad(short: chord.quality) else { return [TriadPathStep]() }
            return TriadVoicings.voicings(root: chord.root, triad: triad)
                .filter { $0.tones.map(\.position.string) == target }
                .map { TriadPathStep(id: "\(chord.roman):\($0.id)", chord: chord, voicing: $0) }
        }.sorted {
            if $0.voicing.minFret != $1.voicing.minFret { return $0.voicing.minFret < $1.voicing.minFret }
            if $0.voicing.maxFret != $1.voicing.maxFret { return $0.voicing.maxFret < $1.voicing.maxFret }
            if $0.chord.degree != $1.chord.degree { return $0.chord.degree < $1.chord.degree }
            return $0.voicing.inversion < $1.voicing.inversion
        }
    }
}
