import Foundation

/// One fret-or-mute per string, in `GuitarTuning` order (0 = Low E ... 5 =
/// High E).
struct ChordFingering: Sendable {
    let string: Int
    let fret: Int
    let midiNote: Int
    let isRoot: Bool
}

/// Standard "cowboy"/open-position chord charts — the same shapes a
/// songbook or chord-chart app prints — keyed by exact root and quality.
///
/// This exists because deriving a shape from pitch-class math alone can't
/// reproduce these: asked "where's a chord tone on the Low E string" for an
/// open D major, the honest pitch-class answer is "fret 2, that's an F♯" —
/// correct, and also not what any guitarist actually plays, because that
/// string is muted by convention (hand shape, which note you don't want
/// doubled), not by the absence of a chord tone there. No amount of chroma
/// or interval math can recover a convention; it has to be looked up.
enum ChordShapeLibrary {
    /// `nil` per string means muted. Deliberately only the shapes players
    /// actually reach for in open position — everything else falls back to
    /// `ChordShapeResolver`'s reachable-tone approximation, which fights
    /// this muting problem far less: most other chords are played as barre
    /// shapes, where every string genuinely is meant to ring.
    private static let shapes: [String: [Int?]] = [
        "E-major": [0, 2, 2, 1, 0, 0],
        "E-minor": [0, 2, 2, 0, 0, 0],
        "E-dominantSeventh": [0, 2, 0, 1, 0, 0],
        "E-minorSeventh": [0, 2, 0, 0, 0, 0],
        "A-major": [nil, 0, 2, 2, 2, 0],
        "A-minor": [nil, 0, 2, 2, 1, 0],
        "A-dominantSeventh": [nil, 0, 2, 0, 2, 0],
        "A-minorSeventh": [nil, 0, 2, 0, 1, 0],
        "D-major": [nil, nil, 0, 2, 3, 2],
        "D-minor": [nil, nil, 0, 2, 3, 1],
        "D-dominantSeventh": [nil, nil, 0, 2, 1, 2],
        "D-minorSeventh": [nil, nil, 0, 2, 1, 1],
        "G-major": [3, 2, 0, 0, 0, 3],
        "G-dominantSeventh": [3, 2, 0, 0, 0, 1],
        "C-major": [nil, 3, 2, 0, 1, 0],
        "C-dominantSeventh": [nil, 3, 2, 3, 1, 0],
        "B-dominantSeventh": [nil, 2, 1, 2, 0, 2],
    ]

    static func shape(for chord: ChordMatch, tuning: Tuning) -> [Int?]? {
        // These arrays encode finger positions, not just chord tones; applying
        // one after retuning would produce a familiar-looking but wrong chart.
        guard tuning.id == .standard else { return nil }
        return shapes["\(chord.root)-\(chord.quality.rawValue)"]
    }
}

/// Unlike `FretPositionResolver`, this has no hand-history to disambiguate
/// with: a chord is six strings struck together, not one note traced across
/// time.
enum ChordShapeResolver {
    /// The canonical open-position shape when `ChordShapeLibrary` has one;
    /// otherwise every chord tone reachable within `reach` frets per
    /// string. That fallback is an approximation — without a canonical
    /// shape there's no muting convention available to apply, only "is a
    /// chord tone here," so it can mark strings a real player would mute.
    static func fingering(for chord: ChordMatch, tuning: Tuning = Tunings.standard, reach: Int = 4) -> [ChordFingering] {
        guard let root = NoteMapper.pitchClassNames.firstIndex(of: chord.root) else { return [] }
        if let shape = ChordShapeLibrary.shape(for: chord, tuning: tuning) {
            return fingering(fromShape: shape, root: root, tuning: tuning)
        }
        return reachableFingering(root: root, chord: chord, tuning: tuning, reach: reach)
    }

    private static func fingering(fromShape shape: [Int?], root: Int, tuning: Tuning) -> [ChordFingering] {
        shape.enumerated().compactMap { string, fret in
            guard let fret else { return nil }
            let midi = tuning.openMIDINotes[string] + fret
            let pitchClass = ((midi % 12) + 12) % 12
            return ChordFingering(string: string, fret: fret, midiNote: midi, isRoot: pitchClass == root)
        }
    }

    /// How far up the neck to look per string before giving up on it. 4
    /// frets covers a first-position hand span.
    private static func reachableFingering(root: Int, chord: ChordMatch, tuning: Tuning, reach: Int) -> [ChordFingering] {
        let tones = Set(chord.quality.intervals.map { (root + $0) % 12 })
        return tuning.openMIDINotes.enumerated().flatMap { string, open -> [ChordFingering] in
            (0...reach).compactMap { fret in
                let midi = open + fret
                let pitchClass = ((midi % 12) + 12) % 12
                guard tones.contains(pitchClass) else { return nil }
                return ChordFingering(string: string, fret: fret, midiNote: midi, isRoot: pitchClass == root)
            }
        }
    }
}
