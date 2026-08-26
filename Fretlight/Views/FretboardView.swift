import SwiftUI

/// The listening screen's board.
///
/// Almost nothing is left here: deriving the markers moved to
/// `DetectionBoardAdapter`, drawing the neck to `BoardCanvas`, and placing and
/// animating the dots to `FretboardBoardView`. What remains is the part that
/// is specific to listening rather than to fretboards — how the board should
/// describe itself aloud when it is reporting one detected thing rather than
/// showing a shape.
struct FretboardView: View {
    let mode: DetectionMode
    let note: MappedNote?
    /// Every position the note could be played at, the resolver's pick first.
    /// Only consulted in `.notes` mode.
    let positions: [RankedPosition]
    /// Only consulted in `.chords` mode.
    let chord: ChordMatch?
    /// Display orientation only. `GuitarTuning`'s string indices (0 = Low E
    /// ... 5 = High E) never change; this just tells `BoardGeometry` which
    /// screen row to draw each index at.
    let flipped: Bool
    private let frets = 22

    var body: some View {
        // The general board animates on its dots, which change exactly when
        // the detected note or chord does — the ids encode the MIDI note and
        // the chord name, and nothing else about a detection reaches them. So
        // the separate animation key this view used to carry is no longer
        // holding anything up.
        FretboardBoardView(
            dots: DetectionBoardAdapter.dots(mode: mode, note: note, positions: positions, chord: chord),
            frets: frets,
            flipped: flipped
        )
        // Overrides the general board's own summary. Listening has a better
        // answer available than "how many dots are on the board": it knows
        // which single position the resolver actually picked, which is the
        // thing a player asking their screen out loud wants to hear.
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        switch mode {
        case .notes:
            guard let note, let pick = positions.first(where: \.isPrimary) else { return "No note detected" }
            let fret = pick.position.fret == 0 ? "open" : "fret \(pick.position.fret)"
            return "\(note.name)\(note.octave), \(GuitarTuning.stringNames[pick.position.string]) string, \(fret)"
        case .chords:
            guard let chord else { return "No chord detected" }
            let shape = ChordShapeResolver.fingering(for: chord).sorted { $0.string < $1.string }
                .map { "\(GuitarTuning.stringNames[$0.string]) \($0.fret == 0 ? "open" : "fret \($0.fret)")" }
                .joined(separator: ", ")
            return "\(chord.name) chord: \(shape)"
        }
    }
}
