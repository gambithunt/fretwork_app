import XCTest
@testable import Fretwork

final class ChordShapeResolverTests: XCTestCase {
    private func fret(_ fingering: [ChordFingering], string: Int) -> Int? {
        fingering.first { $0.string == string }?.fret
    }

    /// D major's standard open-position shape (x-0-0-2-3-2) falls straight
    /// out of "closest chord tone to the nut, per string" — no special-casing
    /// needed, which is the whole point of resolving it that way.
    func testOpenDMajorReproducesTheStandardShape() {
        let chord = ChordMatch(root: "D", quality: .major, confidence: 1)
        let fingering = ChordShapeResolver.fingering(for: chord)
        XCTAssertEqual(fret(fingering, string: 1), 0) // A string, open
        XCTAssertEqual(fret(fingering, string: 2), 0) // D string, open
        XCTAssertEqual(fret(fingering, string: 3), 2) // G string, fret 2
        XCTAssertEqual(fret(fingering, string: 4), 3) // B string, fret 3
        XCTAssertEqual(fret(fingering, string: 5), 2) // High E, fret 2
    }

    func testRootStringIsFlagged() {
        let chord = ChordMatch(root: "A", quality: .minor, confidence: 1)
        let fingering = ChordShapeResolver.fingering(for: chord)
        // A string open is the root.
        XCTAssertTrue(fingering.first { $0.string == 1 }?.isRoot ?? false)
    }

    func testUnknownRootReturnsNoFingering() {
        let chord = ChordMatch(root: "H", quality: .major, confidence: 1)
        XCTAssertTrue(ChordShapeResolver.fingering(for: chord).isEmpty)
    }
}
