import Foundation

enum TriadPathStringSet: String, CaseIterable, Sendable {
    case ead = "E–A–D"
    case adg = "A–D–G"
    case dgb = "D–G–B"
    case gbe = "G–B–E"
}

struct TriadPathStep: Sendable {
    let id: String
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

    /// Harmony selection belongs to the later diatonic layer, so this takes
    /// its triad explicitly while preserving the source path's neck ordering.
    static func path(root: PitchClass, triad: ChordDef, stringSet: TriadPathStringSet) -> [TriadPathStep] {
        let target = stringIndices(for: stringSet)
        return TriadVoicings.voicings(root: root, triad: triad)
            .filter { $0.tones.map(\.position.string) == target }
            .map { TriadPathStep(id: "\(triad.short):\($0.id)", voicing: $0) }
            .sorted {
                $0.voicing.minFret == $1.voicing.minFret
                    ? $0.voicing.maxFret < $1.voicing.maxFret
                    : $0.voicing.minFret < $1.voicing.minFret
            }
    }
}
