import Foundation

enum TuningID: String, Sendable, CaseIterable {
    case standard
    case standardC
    case standardD
    case dropD
    case dropC
    case dropB
    case dropA
    case doubleDropD
    case openG
    case openD
    case openE
    case openC
    case openA
    case modalC6
    case dadgad
}

struct Tuning: Sendable, Hashable {
    let id: TuningID
    let name: String
    /// MIDI notes run from the lowest string at index 0 to the highest at 5.
    let openMIDINotes: [Int]

    /// Kept derived from MIDI rather than duplicated in every definition, so
    /// a tuning's label cannot drift away from the pitches it actually maps.
    var display: String {
        openMIDINotes.map { PitchClass($0).name() }.joined(separator: "-")
    }

    /// Standard tuning has an E at both ends, so the outer strings are
    /// qualified to tell them apart — the labelling the app has always used.
    /// Applied to every tuning rather than only when the two ends actually
    /// collide, so a given string's label never changes shape between tunings.
    var stringNames: [String] {
        openMIDINotes.enumerated().map { index, midi in
            let name = PitchClass(midi).name()
            if index == 0 { return "Low \(name)" }
            if index == openMIDINotes.count - 1 { return "High \(name)" }
            return name
        }
    }
}

enum Tunings: Sendable {
    static let standard = Tuning(id: .standard, name: "Standard", openMIDINotes: [40, 45, 50, 55, 59, 64])
    static let standardC = Tuning(id: .standardC, name: "Standard C", openMIDINotes: [36, 41, 46, 51, 55, 60])
    static let standardD = Tuning(id: .standardD, name: "Standard D", openMIDINotes: [38, 43, 48, 53, 57, 62])
    static let dropD = Tuning(id: .dropD, name: "Drop D", openMIDINotes: [38, 45, 50, 55, 59, 64])
    static let dropC = Tuning(id: .dropC, name: "Drop C", openMIDINotes: [36, 43, 48, 53, 57, 62])
    static let dropB = Tuning(id: .dropB, name: "Drop B", openMIDINotes: [35, 42, 47, 52, 56, 61])
    static let dropA = Tuning(id: .dropA, name: "Drop A", openMIDINotes: [33, 40, 45, 50, 54, 59])
    static let doubleDropD = Tuning(id: .doubleDropD, name: "Double Drop D", openMIDINotes: [38, 45, 50, 55, 59, 62])
    static let openG = Tuning(id: .openG, name: "Open G", openMIDINotes: [38, 43, 50, 55, 59, 62])
    static let openD = Tuning(id: .openD, name: "Open D", openMIDINotes: [38, 45, 50, 54, 57, 62])
    static let openE = Tuning(id: .openE, name: "Open E", openMIDINotes: [40, 47, 52, 56, 59, 64])
    static let openC = Tuning(id: .openC, name: "Open C", openMIDINotes: [36, 43, 48, 55, 60, 64])
    static let openA = Tuning(id: .openA, name: "Open A", openMIDINotes: [40, 45, 49, 52, 57, 64])
    static let modalC6 = Tuning(id: .modalC6, name: "Modal C6", openMIDINotes: [36, 45, 48, 55, 60, 64])
    static let dadgad = Tuning(id: .dadgad, name: "DADGAD", openMIDINotes: [38, 45, 50, 55, 57, 62])

    /// UI selection order is product order, so it stays explicit rather than
    /// being recovered from identifiers or a dictionary's implementation.
    static let all: [Tuning] = [standard, standardC, standardD, dropD, dropC, dropB, dropA, doubleDropD, openG, openD, openE, openC, openA, modalC6, dadgad]

    static func tuning(id: TuningID) -> Tuning {
        all.first { $0.id == id } ?? standard
    }

    /// A persisted selection may outlive a renamed or removed option, where
    /// falling back to standard is safer than creating an invalid neck.
    static func tuning(id: String) -> Tuning {
        guard let id = TuningID(rawValue: id) else { return standard }
        return tuning(id: id)
    }
}
