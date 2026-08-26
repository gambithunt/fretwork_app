import SwiftUI

/// Turns detection state — a note or a chord, depending on `DetectionMode` —
/// into the general board's `FretboardDot`s.
///
/// Lifted verbatim from `FretboardView.activeMarkers`, which used to compute
/// this inline: the id formats, the notes-mode sort, and the chords-mode
/// root/non-root colour split are all reproduced exactly rather than
/// reconsidered, so the detection board reads identically once the view
/// becomes a thin consumer of this instead of deriving markers itself.
enum DetectionBoardAdapter {
    /// - Parameters:
    ///   - mode: which pair below is consulted. The other pair is ignored
    ///     even if it happens to be populated.
    ///   - note: the currently detected pitch. Only consulted in `.notes`.
    ///   - positions: every position `note` could be played at, ranked by
    ///     `FretPositionResolver`. Only consulted in `.notes`.
    ///   - chord: the currently detected chord. Only consulted in `.chords`.
    static func dots(
        mode: DetectionMode,
        note: MappedNote?,
        positions: [RankedPosition],
        chord: ChordMatch?
    ) -> [FretboardDot] {
        switch mode {
        case .notes:
            return noteDots(note: note, positions: positions)
        case .chords:
            return chordDots(chord: chord)
        }
    }

    /// Every position the note could be played at, sorted by string then
    /// fret — not by the resolver's rank, which only decides which single
    /// position is primary elsewhere. Here every reachable spot is shown, so
    /// the natural order is the neck's own, low string first.
    private static func noteDots(note: MappedNote?, positions: [RankedPosition]) -> [FretboardDot] {
        guard let note else { return [] }
        return positions.sorted {
            $0.position.string == $1.position.string
                ? $0.position.fret < $1.position.fret
                : $0.position.string < $1.position.string
        }
        .map { ranked in
            FretboardDot(
                id: "\(note.midiNote)-\(ranked.position.string)-\(ranked.position.fret)",
                position: ranked.position,
                label: "\(note.name)\(note.octave)",
                color: NotePalette.color(for: note.name)
            )
        }
    }

    /// Every fingering `ChordShapeResolver` returns for the chord. A muted
    /// string produces no fingering at all, so it produces no dot here
    /// either. Root tones keep the chord's own colour; the rest fall back to
    /// a plain translucent white so the root reads as the shape's anchor,
    /// exactly as `FretboardView.activeMarkers` drew it — `role` carries that
    /// same distinction forward for the accessible description, since it
    /// isn't itself drawn.
    private static func chordDots(chord: ChordMatch?) -> [FretboardDot] {
        guard let chord else { return [] }
        return ChordShapeResolver.fingering(for: chord).map { fingering in
            let label = NoteMapper.pitchClassNames[((fingering.midiNote % 12) + 12) % 12]
            let position = FretPosition(string: fingering.string, fret: fingering.fret)
            return FretboardDot(
                id: "\(chord.name)-\(fingering.string)-\(fingering.fret)",
                position: position,
                label: label,
                color: fingering.isRoot ? NotePalette.color(for: chord.root) : .white.opacity(0.4),
                role: fingering.isRoot ? "root" : nil
            )
        }
    }
}
