import Foundation

/// One fret per string for a detected chord, so the fretboard can draw the
/// chord as a *shape* — a chart, one fret-or-mute per string — rather than
/// lighting up every occurrence of every chord tone across all 22 frets.
struct ChordFingering: Sendable {
    let string: Int
    let fret: Int
    let midiNote: Int
    let isRoot: Bool
}

/// Unlike `FretPositionResolver`, this has no hand-history to disambiguate
/// with: a chord is six strings struck together, not one note traced across
/// time. "Closest to the nut" stands in for "the shape a player would
/// actually reach for" — which is also why this reliably reproduces the
/// standard open-position shape for a chord that has one (see
/// `ChordShapeResolverTests`).
enum ChordShapeResolver {
    /// How far up the neck to look per string before giving up on it. 4
    /// frets covers every stock open-position chord shape; a string with no
    /// chord tone in that span is left out of the returned array rather
    /// than reaching further, since that would stop reading as one shape.
    static func fingering(for chord: ChordMatch, reach: Int = 4) -> [ChordFingering] {
        guard let root = NoteMapper.pitchClassNames.firstIndex(of: chord.root) else { return [] }
        let tones = Set(chord.quality.intervals.map { (root + $0) % 12 })
        return GuitarTuning.openMIDINotes.enumerated().compactMap { string, open in
            for fret in 0...reach {
                let midi = open + fret
                let pitchClass = ((midi % 12) + 12) % 12
                guard tones.contains(pitchClass) else { continue }
                return ChordFingering(string: string, fret: fret, midiNote: midi, isRoot: pitchClass == root)
            }
            return nil
        }
    }
}
