import XCTest
@testable import Fretwork

final class ChordHistoryTests: XCTestCase {
    private func match(_ root: String, _ quality: ChordQuality = .major) -> ChordMatch {
        ChordMatch(root: root, quality: quality, confidence: 1)
    }

    func testDifferentChordAppends() {
        let history = AppState.appending(match("C"), to: [], limit: 10)
        XCTAssertEqual(history.map(\.match.name), ["C"])
    }

    /// The worker republishes its locked chord every poll tick while a
    /// chord is held, not just on the strum onset that produced it — this
    /// is the dedup that keeps that from spamming the log.
    func testSameChordRepeatedDoesNotDuplicate() {
        var history = AppState.appending(match("C"), to: [], limit: 10)
        history = AppState.appending(match("C"), to: history, limit: 10)
        history = AppState.appending(match("C"), to: history, limit: 10)
        XCTAssertEqual(history.map(\.match.name), ["C"])
    }

    func testNilMatchIsANoOp() {
        let history = AppState.appending(match("C"), to: [], limit: 10)
        XCTAssertEqual(AppState.appending(nil, to: history, limit: 10), history)
    }

    /// Dedup compares only against the immediately preceding entry, not
    /// every entry seen — this is a strum log, not a "chords seen so far"
    /// set, so a chord returned to after something else in between logs
    /// again.
    func testChordReturnedToAfterAnotherLogsAgain() {
        var history = AppState.appending(match("A", .minor), to: [], limit: 10)
        history = AppState.appending(match("F"), to: history, limit: 10)
        history = AppState.appending(match("A", .minor), to: history, limit: 10)
        XCTAssertEqual(history.map(\.match.name), ["Am", "F", "Am"])
    }

    func testCapDropsTheOldestEntryFirst() {
        var history: [ChordHistoryEntry] = []
        let roots = ["C", "D", "E", "F", "G", "A", "B", "C", "D", "E", "F"]
        for (index, root) in roots.enumerated() {
            // Alternate quality so adjacent entries are never equal and each
            // one actually appends.
            let quality: ChordQuality = index.isMultiple(of: 2) ? .major : .minor
            history = AppState.appending(match(root, quality), to: history, limit: 10)
        }
        XCTAssertEqual(history.count, 10)
        XCTAssertEqual(history.first?.match.name, "Dm") // the first "C" fell off
        XCTAssertEqual(history.last?.match.name, "F")
    }
}
