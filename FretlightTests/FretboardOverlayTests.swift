import XCTest
import SwiftUI
@testable import Fretwork

final class FretboardOverlayTests: XCTestCase {
    private static let dots: [FretboardDot] = [
        FretboardDot(id: "a", position: FretPosition(string: 0, fret: 0), label: "E", color: .red),
        FretboardDot(id: "b", position: FretPosition(string: 1, fret: 2), label: "B", color: .red),
        FretboardDot(id: "c", position: FretPosition(string: 2, fret: 2), label: "G", color: .red),
        FretboardDot(id: "d", position: FretPosition(string: 3, fret: 0), label: "D", color: .red),
    ]

    /// The dots array is a, b, c, d; the overlay declares a path that visits
    /// them in a different order. Resolution must follow the overlay, not the
    /// array — proving order is actually carried through, not incidentally
    /// preserved because the two happened to match.
    func testSequenceResolvesInTheOverlaysDeclaredOrderNotTheDotsArrayOrder() {
        let overlay = FretboardOverlay(id: "run", kind: .sequence, color: .blue, dotIDs: ["c", "a", "d", "b"])
        let resolved = overlay.resolve(against: Self.dots)
        XCTAssertEqual(resolved.map(\.id), ["c", "a", "d", "b"])
    }

    func testGroupResolvesToTheRightDotsDeterministicallyAcrossRepeatedCalls() {
        let overlay = FretboardOverlay(id: "box", kind: .group, color: .green, dotIDs: ["d", "b"])
        let first = overlay.resolve(against: Self.dots).map(\.id)
        let second = overlay.resolve(against: Self.dots).map(\.id)
        XCTAssertEqual(Set(first), Set(["b", "d"]))
        XCTAssertEqual(first, second, "resolving the same overlay against the same dots twice must not change the order")
    }

    func testAnOverlayReferencingAnUnknownDotIDSkipsItAndStillResolvesTheRest() {
        let sequence = FretboardOverlay(id: "run", kind: .sequence, color: .blue, dotIDs: ["a", "ghost", "b"])
        XCTAssertEqual(sequence.resolve(against: Self.dots).map(\.id), ["a", "b"])

        let group = FretboardOverlay(id: "box", kind: .group, color: .green, dotIDs: ["ghost", "c"])
        XCTAssertEqual(group.resolve(against: Self.dots).map(\.id), ["c"])
    }

    /// Ids are meant to be unique, and a duplicate means a module built its
    /// dots wrongly. That should surface as a misdrawn overlay, not as a trap
    /// inside a dictionary initialiser taking the whole app down.
    func testDuplicateDotIDsDoNotTrap() {
        let duplicated = Self.dots + [FretboardDot(
            id: "a",
            position: FretPosition(string: 5, fret: 12),
            label: "dupe",
            color: .red
        )]
        let sequence = FretboardOverlay(id: "run", kind: .sequence, color: .blue, dotIDs: ["a", "b"])
        XCTAssertEqual(sequence.resolve(against: duplicated).map(\.id), ["a", "b"])

        let group = FretboardOverlay(id: "box", kind: .group, color: .green, dotIDs: ["a"])
        XCTAssertEqual(group.resolve(against: duplicated).count, 2, "a group keeps both, since it filters rather than keying")
    }

    func testAnEmptyOverlayResolvesToNoDots() {
        let overlay = FretboardOverlay(id: "empty", kind: .group, color: .green, dotIDs: [])
        XCTAssertTrue(overlay.resolve(against: Self.dots).isEmpty)
    }
}
