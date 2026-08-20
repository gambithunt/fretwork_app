import Foundation

/// Every open-position fret on a string that sounds one of the chord's
/// tones — not just the nearest one. Chroma detection can't tell *which*
/// voicing was actually strummed (a 3-finger open G and the 4-finger
/// variant that also frets the B string are the same pitch classes), so
/// rather than guess a single shape, `ChordShapeResolver` surfaces every
/// reachable position and lets the fretboard show them all — see
/// `fingering(for:reach:)`.
struct ChordFingering: Sendable {
    let string: Int
    let fret: Int
    let midiNote: Int
    let isRoot: Bool
}

/// Unlike `FretPositionResolver`, this has no hand-history to disambiguate
/// with: a chord is six strings struck together, not one note traced across
/// time, and chroma alone can't distinguish an open string ringing from the
/// same pitch class fretted a few frets up. "Every chord tone within reach"
/// is the honest answer to "where could this have been played" — it's also
/// why this reliably reproduces the standard open-position shape for a
/// chord that has one, alongside its common alternate voicings (see
/// `ChordShapeResolverTests`).
enum ChordShapeResolver {
    /// How far up the neck to look per string. 4 frets covers every stock
    /// open-position chord shape and its usual alternate voicings; a string
    /// with no chord tone in that span is left out of the returned array
    /// rather than reaching further, since that would stop reading as one
    /// coherent hand position.
    static func fingering(for chord: ChordMatch, reach: Int = 4) -> [ChordFingering] {
        guard let root = NoteMapper.pitchClassNames.firstIndex(of: chord.root) else { return [] }
        let tones = Set(chord.quality.intervals.map { (root + $0) % 12 })
        return GuitarTuning.openMIDINotes.enumerated().flatMap { string, open -> [ChordFingering] in
            (0...reach).compactMap { fret in
                let midi = open + fret
                let pitchClass = ((midi % 12) + 12) % 12
                guard tones.contains(pitchClass) else { return nil }
                return ChordFingering(string: string, fret: fret, midiNote: midi, isRoot: pitchClass == root)
            }
        }
    }
}
