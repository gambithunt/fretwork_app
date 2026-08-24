import Foundation

struct ChordShape: Sendable {
    let id: String
    let name: String
    let root: PitchClass
    /// Low E through high E; nil records a string the conventional shape mutes.
    let frets: [Int?]
}

struct ChordVoicing: Sendable {
    let id: String
    let shape: String
    let frets: [Int?]
    let minFret: Int
    let maxFret: Int
    let isOpen: Bool
}

private struct ChordFormulaShapes: Sendable {
    let formulaID: String
    let shapes: [ChordShape]
}

enum ChordVoicings: Sendable {
    static let fretCount = 15

    /// Major keeps all five CAGED families, while minor keeps only the three
    /// complete movable forms players can use without awkward omissions.
    private static let majorShapes = [
        ChordShape(id: "c", name: "C-shape", root: PitchClass(0), frets: [nil, 3, 2, 0, 1, 0]),
        ChordShape(id: "a", name: "A-shape", root: PitchClass(9), frets: [nil, 0, 2, 2, 2, 0]),
        ChordShape(id: "g", name: "G-shape", root: PitchClass(7), frets: [3, 2, 0, 0, 0, 3]),
        ChordShape(id: "e", name: "E-shape", root: PitchClass(4), frets: [0, 2, 2, 1, 0, 0]),
        ChordShape(id: "d", name: "D-shape", root: PitchClass(2), frets: [nil, nil, 0, 2, 3, 2])
    ]

    private static let minorShapes = [
        ChordShape(id: "a", name: "A-shape", root: PitchClass(9), frets: [nil, 0, 2, 2, 1, 0]),
        ChordShape(id: "e", name: "E-shape", root: PitchClass(4), frets: [0, 2, 2, 0, 0, 0]),
        ChordShape(id: "d", name: "D-shape", root: PitchClass(2), frets: [nil, nil, 0, 2, 3, 1])
    ]

    /// Both forms carry the octave root, while deliberately omitting a third.
    private static let powerShapes = [
        ChordShape(id: "power-e", name: "E-string root", root: PitchClass(4), frets: [0, 2, 2, nil, nil, nil]),
        ChordShape(id: "power-a", name: "A-string root", root: PitchClass(9), frets: [nil, 0, 2, 2, nil, nil])
    ]

    private static let formulaShapes = [
        ChordFormulaShapes(formulaID: "maj", shapes: majorShapes),
        ChordFormulaShapes(formulaID: "min", shapes: minorShapes),
        ChordFormulaShapes(formulaID: "power", shapes: powerShapes),
        ChordFormulaShapes(formulaID: "7", shapes: [ChordShape(id: "e7", name: "E-string root", root: PitchClass(4), frets: [0, 2, 0, 1, 0, 0])]),
        ChordFormulaShapes(formulaID: "maj7", shapes: [ChordShape(id: "emaj7", name: "E-string root", root: PitchClass(4), frets: [0, 2, 1, 1, 0, 0])]),
        ChordFormulaShapes(formulaID: "m7", shapes: [ChordShape(id: "em7", name: "E-string root", root: PitchClass(4), frets: [0, 2, 0, 0, 0, 0])]),
        ChordFormulaShapes(formulaID: "m7b5", shapes: [ChordShape(id: "em7b5", name: "E-string root", root: PitchClass(4), frets: [0, 1, 0, 0, 3, 0])]),
        ChordFormulaShapes(formulaID: "sus2", shapes: [ChordShape(id: "esus2", name: "E-string root", root: PitchClass(4), frets: [0, 2, 4, 4, 0, 0])]),
        ChordFormulaShapes(formulaID: "sus4", shapes: [ChordShape(id: "esus4", name: "E-string root", root: PitchClass(4), frets: [0, 2, 2, 2, 0, 0])]),
        ChordFormulaShapes(formulaID: "add9", shapes: [ChordShape(id: "dadd9", name: "D-shape", root: PitchClass(2), frets: [nil, nil, 4, 2, 3, 0])]),
        ChordFormulaShapes(formulaID: "6", shapes: [ChordShape(id: "e6", name: "E-string root", root: PitchClass(4), frets: [0, 2, 2, 1, 2, 0])]),
        ChordFormulaShapes(formulaID: "m6", shapes: [ChordShape(id: "em6", name: "E-string root", root: PitchClass(4), frets: [0, 2, 2, 0, 2, 0])]),
        ChordFormulaShapes(formulaID: "9", shapes: [ChordShape(id: "e9", name: "E-string root", root: PitchClass(4), frets: [0, nil, 0, 1, 0, 2])]),
        ChordFormulaShapes(formulaID: "maj9", shapes: [ChordShape(id: "emaj9", name: "E-string root", root: PitchClass(4), frets: [0, nil, 1, 1, 0, 2])]),
        ChordFormulaShapes(formulaID: "m9", shapes: [ChordShape(id: "em9", name: "E-string root", root: PitchClass(4), frets: [0, nil, 0, 0, 0, 2])]),
        ChordFormulaShapes(formulaID: "13", shapes: [ChordShape(id: "e13", name: "E-string root", root: PitchClass(4), frets: [0, nil, 0, 4, 2, 4])])
    ]

    static func voicings(root: PitchClass, formulaID: String) -> [ChordVoicing] {
        guard let shapes = formulaShapes.first(where: { $0.formulaID == formulaID })?.shapes else { return [] }
        return shapes.map { transpose($0, to: root) }.sorted {
            $0.minFret == $1.minFret ? $0.maxFret < $1.maxFret : $0.minFret < $1.minFret
        }
    }

    static func lowestPositionID(root: PitchClass, formulaID: String) -> String? {
        voicings(root: root, formulaID: formulaID).first?.id
    }

    /// The pitch-class shift is bounded to one octave; the curated source
    /// shapes were selected so that this leaves every result on the 15-fret
    /// reference board without inventing a second position for the same form.
    private static func transpose(_ shape: ChordShape, to root: PitchClass) -> ChordVoicing {
        let shift = (root.value - shape.root.value + 12) % 12
        let frets = shape.frets.map { $0.map { $0 + shift } }
        let sounding = frets.compactMap { $0 }
        return ChordVoicing(
            id: shape.id,
            shape: shape.name,
            frets: frets,
            minFret: sounding.min() ?? 0,
            maxFret: sounding.max() ?? 0,
            isOpen: shift == 0
        )
    }
}
