import Foundation

/// One distinct chord the player has actually strummed, kept for the
/// history strip. Holds the full `ChordMatch` (not just its name) because
/// tapping a chip needs to hand `FretboardView` back a real match to
/// re-derive its shape — `ChordShapeResolver` takes nothing less.
struct ChordHistoryEntry: Sendable, Equatable, Identifiable {
    let id: UUID
    let match: ChordMatch

    init(match: ChordMatch) {
        self.id = UUID()
        self.match = match
    }
}
