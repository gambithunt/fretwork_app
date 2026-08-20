import Foundation

/// One distinct note the player has actually fretted, kept for the notes-mode
/// history strip. Carries its own `positions` snapshot rather than the note
/// alone, because `FretPositionResolver` is stateful hand-position tracking —
/// re-resolving a past note's position on tap would perturb the live
/// estimate. Instead each entry freezes exactly what the board showed at the
/// moment the note was played.
struct NoteHistoryEntry: Sendable, Identifiable {
    let id: UUID
    let note: MappedNote
    let positions: [RankedPosition]

    init(note: MappedNote, positions: [RankedPosition]) {
        self.id = UUID()
        self.note = note
        self.positions = positions
    }
}
