import Foundation

struct OctaveShape: Sendable {
    let root: NeckPosition
    let target: NeckPosition
    let fretOffset: Int
}

enum OctaveShapes: Sendable {
    static func shapes(root: PitchClass, tuning: Tuning = Tunings.standard, fretCount: Int) -> [OctaveShape] {
        Positions.findAll(pitchClasses: [root], tuning: tuning, fretCount: fretCount).compactMap { position in
            // Subtracting two moves up in the web's high-first indexing; here
            // the same physical move is toward the higher string at +2.
            let targetString = position.string + 2
            guard tuning.openMIDINotes.indices.contains(targetString) else { return nil }
            let targetMIDI = position.midiNote + 12
            let targetFret = targetMIDI - tuning.openMIDINotes[targetString]
            guard (0...fretCount).contains(targetFret) else { return nil }
            let target = NeckPosition(string: targetString, fret: targetFret, midiNote: targetMIDI, pitchClass: PitchClass(targetMIDI))
            return OctaveShape(root: position, target: target, fretOffset: targetFret - position.fret)
        }
    }

    static func resolve(shapes: [OctaveShape], preferred: NeckPosition) -> OctaveShape? {
        guard !shapes.isEmpty else { return nil }
        if let exact = shapes.first(where: { $0.root.string == preferred.string && $0.root.fret == preferred.fret }) { return exact }
        return shapes.min { distance($0.root, preferred) < distance($1.root, preferred) }
    }

    private static func distance(_ left: NeckPosition, _ right: NeckPosition) -> Int {
        abs(left.fret - right.fret) + abs(left.string - right.string) * 2
    }
}
