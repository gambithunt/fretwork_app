import XCTest
@testable import Fretwork

final class FretboardNavigationTests: XCTestCase {
    private static let anchors = [
        FretPosition(string: 0, fret: 0),
        FretPosition(string: 0, fret: 5),
        FretPosition(string: 0, fret: 7),
        FretPosition(string: 0, fret: 10),
    ]

    func testNextMovesOneStepAndReturnsTrue() {
        var navigation = FretboardNavigation(anchors: Self.anchors, selected: Self.anchors[0])
        XCTAssertTrue(navigation.next())
        XCTAssertEqual(navigation.selected, Self.anchors[1])
    }

    func testPreviousMovesOneStepAndReturnsTrue() {
        var navigation = FretboardNavigation(anchors: Self.anchors, selected: Self.anchors[2])
        XCTAssertTrue(navigation.previous())
        XCTAssertEqual(navigation.selected, Self.anchors[1])
    }

    func testNextAtTheLastAnchorDoesNotMoveAndReturnsFalse() {
        var navigation = FretboardNavigation(anchors: Self.anchors, selected: Self.anchors.last)
        XCTAssertFalse(navigation.next())
        XCTAssertEqual(navigation.selected, Self.anchors.last)
    }

    func testPreviousAtTheFirstAnchorDoesNotMoveAndReturnsFalse() {
        var navigation = FretboardNavigation(anchors: Self.anchors, selected: Self.anchors.first)
        XCTAssertFalse(navigation.previous())
        XCTAssertEqual(navigation.selected, Self.anchors.first)
    }

    func testAnEmptyAnchorListReturnsFalseFromBothWithoutTrapping() {
        let unchanged = FretPosition(string: 0, fret: 0)
        var navigation = FretboardNavigation(anchors: [], selected: unchanged)
        XCTAssertFalse(navigation.next())
        XCTAssertFalse(navigation.previous())
        XCTAssertEqual(navigation.selected, unchanged, "a failed step must not alter the selection")
    }

    /// A selection that isn't one of the anchors (e.g. the board scrolled to
    /// a free position between boxes) has no index to step from. Rather than
    /// trapping or guessing an offset, the first step of either direction
    /// lands on the list's first anchor and reports a move — the same thing
    /// a first arrow-key press should do when nothing on the list is
    /// highlighted yet.
    func testASelectionNotInTheAnchorListRecoversToTheFirstAnchor() {
        let stray = FretPosition(string: 3, fret: 2)
        var next = FretboardNavigation(anchors: Self.anchors, selected: stray)
        XCTAssertTrue(next.next())
        XCTAssertEqual(next.selected, Self.anchors.first)

        var previous = FretboardNavigation(anchors: Self.anchors, selected: stray)
        XCTAssertTrue(previous.previous())
        XCTAssertEqual(previous.selected, Self.anchors.first)
    }

    func testNoSelectionRecoversToTheFirstAnchor() {
        var navigation = FretboardNavigation(anchors: Self.anchors, selected: nil)
        XCTAssertTrue(navigation.next())
        XCTAssertEqual(navigation.selected, Self.anchors.first)
    }
}
