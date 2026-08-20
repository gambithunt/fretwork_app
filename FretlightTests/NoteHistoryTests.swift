import XCTest
@testable import Fretwork

final class NoteHistoryTests: XCTestCase {
    private func note(_ midi: Int) -> MappedNote {
        MappedNote(name: NoteMapper.pitchClassNames[(midi % 12 + 12) % 12], octave: midi / 12 - 1, midiNote: midi, cents: 0)
    }

    func testDifferentNoteAppends() {
        let history = AppState.appending(note(64), positions: [], to: [], limit: 10)
        XCTAssertEqual(history.map(\.note.midiNote), [64])
    }

    /// Unlike the chord version, this deliberately does *not* dedup against
    /// the last entry — `resolvePositions` only ever calls it on a genuine
    /// pitch change or a `detectRepick`-caught onset, both real events, and
    /// hitting the same note twice in a row is exactly the case this needs
    /// to support (both hits should show up in the strip).
    func testSameNoteCalledTwiceAppendsTwice() {
        var history = AppState.appending(note(64), positions: [], to: [], limit: 10)
        history = AppState.appending(note(64), positions: [], to: history, limit: 10)
        XCTAssertEqual(history.map(\.note.midiNote), [64, 64])
    }

    func testNilNoteIsANoOp() {
        let history = AppState.appending(note(64), positions: [], to: [], limit: 10)
        XCTAssertEqual(AppState.appending(nil, positions: [], to: history, limit: 10).map(\.note.midiNote), [64])
    }

    func testCapDropsTheOldestEntryFirst() {
        var history: [NoteHistoryEntry] = []
        for midi in 60...70 { // 11 distinct notes
            history = AppState.appending(note(midi), positions: [], to: history, limit: 10)
        }
        XCTAssertEqual(history.count, 10)
        XCTAssertEqual(history.first?.note.midiNote, 61) // the first note (60) fell off
        XCTAssertEqual(history.last?.note.midiNote, 70)
    }

    /// Each entry freezes the resolver's positions at the moment the note
    /// was played, rather than a note alone that would need re-resolving
    /// (and perturbing live hand-tracking) on tap.
    func testEntryCarriesItsOwnPositionsSnapshot() {
        let positions = [RankedPosition(position: FretPosition(string: 1, fret: 2), rank: 0)]
        let history = AppState.appending(note(64), positions: positions, to: [], limit: 10)
        XCTAssertEqual(history.first?.positions, positions)
    }
}
