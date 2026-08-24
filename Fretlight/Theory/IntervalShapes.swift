import Foundation

struct IntervalAnchor: Sendable {
    let root: NeckPosition
    let targets: [NeckPosition]
    let isPlayable: Bool
}

enum IntervalShapes: Sendable {
    static func anchors(root: PitchClass, semitones: Int, tuning: Tuning = Tunings.standard, fretCount: Int) -> [IntervalAnchor] {
        Positions.findAll(pitchClasses: [root], tuning: tuning, fretCount: fretCount).map { position in
            let targetMIDI = position.midiNote + semitones
            let targets = Positions.findAll(pitchClasses: [PitchClass(targetMIDI)], tuning: tuning, fretCount: fretCount)
                .filter { $0.midiNote == targetMIDI }
            return IntervalAnchor(root: position, targets: targets, isPlayable: !targets.isEmpty)
        }
    }

    static func resolve(anchors: [IntervalAnchor], preferred: NeckPosition) -> IntervalAnchor? {
        let playable = anchors.filter(\.isPlayable)
        guard !playable.isEmpty else { return nil }
        if let exact = playable.first(where: { $0.root.string == preferred.string && $0.root.fret == preferred.fret }) { return exact }
        return playable.min { distance($0.root, preferred) < distance($1.root, preferred) }
    }

    private static func distance(_ left: NeckPosition, _ right: NeckPosition) -> Int {
        abs(left.fret - right.fret) + abs(left.string - right.string) * 2
    }
}
