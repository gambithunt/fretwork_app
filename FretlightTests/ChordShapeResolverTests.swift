import XCTest
@testable import Fretwork

final class ChordShapeResolverTests: XCTestCase {
    private func fret(_ fingering: [ChordFingering], string: Int) -> Int? {
        fingering.first { $0.string == string }?.fret
    }

    private func frets(_ fingering: [ChordFingering], string: Int) -> [Int] {
        fingering.filter { $0.string == string }.map(\.fret)
    }

    /// D major's standard open-position shape (x-0-0-2-3-2) falls straight
    /// out of "every chord tone within reach, per string, nearest first" —
    /// no special-casing needed, which is the whole point of resolving it
    /// that way.
    func testOpenDMajorReproducesTheStandardShape() {
        let chord = ChordMatch(root: "D", quality: .major, confidence: 1)
        let fingering = ChordShapeResolver.fingering(for: chord)
        XCTAssertEqual(fret(fingering, string: 1), 0) // A string, open
        XCTAssertEqual(fret(fingering, string: 2), 0) // D string, open
        XCTAssertEqual(fret(fingering, string: 3), 2) // G string, fret 2
        XCTAssertEqual(fret(fingering, string: 4), 3) // B string, fret 3
        XCTAssertEqual(fret(fingering, string: 5), 2) // High E, fret 2
    }

    /// Open G major has two common cowboy voicings — B string ringing open,
    /// or fretted at 3 for the fuller 4-finger version — and chroma alone
    /// can't tell which was actually strummed. Both should surface, not
    /// just whichever is closest to the nut.
    func testOpenGMajorSurfacesBothCommonVoicings() {
        let chord = ChordMatch(root: "G", quality: .major, confidence: 1)
        let fingering = ChordShapeResolver.fingering(for: chord)
        XCTAssertEqual(frets(fingering, string: 4), [0, 3]) // B string: open B, or fret 3 for D
        XCTAssertEqual(frets(fingering, string: 3), [0, 4]) // G string: open G, or fret 4 for B
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
