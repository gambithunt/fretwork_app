import XCTest
@testable import Fretwork

final class ChordShapeResolverTests: XCTestCase {
    private func fret(_ fingering: [ChordFingering], string: Int) -> Int? {
        fingering.first { $0.string == string }?.fret
    }

    /// D major's canonical open-position chart (x-x-0-2-3-2) comes straight
    /// out of `ChordShapeLibrary` — including the two muted strings, which
    /// no amount of reachable-chord-tone math could ever produce (both
    /// strings do have a chord tone within reach; convention mutes them
    /// anyway).
    func testOpenDMajorMatchesTheCanonicalChart() {
        let chord = ChordMatch(root: "D", quality: .major, confidence: 1)
        let fingering = ChordShapeResolver.fingering(for: chord)
        XCTAssertNil(fret(fingering, string: 0)) // Low E: muted
        XCTAssertNil(fret(fingering, string: 1)) // A: muted
        XCTAssertEqual(fret(fingering, string: 2), 0)
        XCTAssertEqual(fret(fingering, string: 3), 2)
        XCTAssertEqual(fret(fingering, string: 4), 3)
        XCTAssertEqual(fret(fingering, string: 5), 2)
        XCTAssertEqual(fingering.count, 4)
    }

    /// Open G major (320003) has two common cowboy voicings in real playing
    /// (B string open, or fretted at 3), but the library commits to the one
    /// method books actually teach as "the" G chord rather than surfacing
    /// both — a fixed chart is what stops the board looking like a stray
    /// F♯-on-the-low-E kind of clutter.
    func testOpenGMajorMatchesTheCanonicalChart() {
        let chord = ChordMatch(root: "G", quality: .major, confidence: 1)
        let fingering = ChordShapeResolver.fingering(for: chord)
        XCTAssertEqual(fret(fingering, string: 0), 3)
        XCTAssertEqual(fret(fingering, string: 1), 2)
        XCTAssertEqual(fret(fingering, string: 2), 0)
        XCTAssertEqual(fret(fingering, string: 3), 0)
        XCTAssertEqual(fret(fingering, string: 4), 0)
        XCTAssertEqual(fret(fingering, string: 5), 3)
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

    /// A quality/root combination with no canonical open shape (an F♯
    /// diminished isn't something method books teach as an open chord)
    /// falls back to "every reachable chord tone" — the approximation this
    /// whole type used before the library existed, still exercised here so
    /// that path stays covered.
    func testChordWithoutACanonicalShapeFallsBackToReachableTones() {
        let chord = ChordMatch(root: "F♯", quality: .diminished, confidence: 1)
        let fingering = ChordShapeResolver.fingering(for: chord)
        XCTAssertFalse(fingering.isEmpty)
        // Every returned position must actually be a tone of F♯ diminished
        // (F♯, A, C).
        let tones: Set<String> = ["F♯", "A", "C"]
        for entry in fingering {
            let name = NoteMapper.pitchClassNames[((entry.midiNote % 12) + 12) % 12]
            XCTAssertTrue(tones.contains(name), "\(name) at string \(entry.string) fret \(entry.fret) isn't an F♯dim tone")
        }
    }
}
