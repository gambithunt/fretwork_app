import XCTest
import SwiftUI
@testable import Fretwork

@MainActor
final class DetectionBoardAdapterTests: XCTestCase {
    /// D3 (MIDI 50) is reachable on three strings in standard tuning: fret 10
    /// on the Low E, fret 5 on the A, and open on the D string — good cover
    /// for both the id format and the string/fret sort.
    private let d3 = MappedNote(name: "D", octave: 3, midiNote: 50, cents: 0)

    private func positions(for midiNote: Int) -> [RankedPosition] {
        FretPositionResolver().resolve(midiNote: midiNote)
    }

    func testNotesModeWithSeveralPositionsProducesExactDotsSortedByStringThenFret() {
        // A cold resolver ranks the lowest fret first (open D, then fret 5,
        // then fret 10) — deliberately not the order the adapter must
        // produce, so this also proves the adapter re-sorts rather than
        // trusting the resolver's rank order.
        let ranked = positions(for: d3.midiNote)
        XCTAssertEqual(ranked.map(\.position), [
            FretPosition(string: 2, fret: 0),
            FretPosition(string: 1, fret: 5),
            FretPosition(string: 0, fret: 10),
        ])

        let dots = DetectionBoardAdapter.dots(mode: .notes, note: d3, positions: ranked, chord: nil)
        let color = NotePalette.color(for: "D")
        XCTAssertEqual(dots, [
            FretboardDot(id: "50-0-10", position: FretPosition(string: 0, fret: 10), label: "D3", color: color),
            FretboardDot(id: "50-1-5", position: FretPosition(string: 1, fret: 5), label: "D3", color: color),
            FretboardDot(id: "50-2-0", position: FretPosition(string: 2, fret: 0), label: "D3", color: color),
        ])
    }

    func testNotesModeWithNoNoteReturnsNoDots() {
        let dots = DetectionBoardAdapter.dots(mode: .notes, note: nil, positions: positions(for: d3.midiNote), chord: nil)
        XCTAssertTrue(dots.isEmpty)
    }

    /// Open D major (x-x-0-2-3-2): the two muted strings from
    /// `ChordShapeLibrary`'s canonical chart must produce no dot at all, and
    /// the two D tones (string 2 open, string 3 fret 3) must be flagged as
    /// root while the A and F♯ are not.
    func testChordsModeWithACanonicalChartProducesExactDotsAndDistinguishesTheRoot() {
        let chord = ChordMatch(root: "D", quality: .major, confidence: 1)
        let dots = DetectionBoardAdapter.dots(mode: .chords, note: nil, positions: [], chord: chord)
        let rootColor = NotePalette.color(for: "D")
        let nonRootColor = Color.white.opacity(0.4)

        XCTAssertEqual(dots, [
            FretboardDot(id: "D-2-0", position: FretPosition(string: 2, fret: 0), label: "D", color: rootColor, role: "root"),
            FretboardDot(id: "D-3-2", position: FretPosition(string: 3, fret: 2), label: "A", color: nonRootColor, role: nil),
            FretboardDot(id: "D-4-3", position: FretPosition(string: 4, fret: 3), label: "D", color: rootColor, role: "root"),
            FretboardDot(id: "D-5-2", position: FretPosition(string: 5, fret: 2), label: "F♯", color: nonRootColor, role: nil),
        ])
        // Strings 0 and 1 are muted by the canonical chart: no dot at all.
        XCTAssertFalse(dots.contains { $0.position.string == 0 || $0.position.string == 1 })
    }

    func testChordsModeWithNoChordReturnsNoDots() {
        let dots = DetectionBoardAdapter.dots(mode: .chords, note: nil, positions: [], chord: nil)
        XCTAssertTrue(dots.isEmpty)
    }

    /// Both a note and a chord are present at once; the mode alone decides
    /// which one's dots come out, and the other must not leak in.
    func testModeSelectsWhichInputProducesDotsWithNoLeakage() {
        let chord = ChordMatch(root: "E", quality: .major, confidence: 1)
        let ranked = positions(for: d3.midiNote)

        let noteDots = DetectionBoardAdapter.dots(mode: .notes, note: d3, positions: ranked, chord: chord)
        XCTAssertEqual(noteDots.map(\.id), ["50-0-10", "50-1-5", "50-2-0"])

        let chordDots = DetectionBoardAdapter.dots(mode: .chords, note: d3, positions: ranked, chord: chord)
        XCTAssertEqual(chordDots.map(\.id), ["E-0-0", "E-1-2", "E-2-2", "E-3-1", "E-4-0", "E-5-0"])
    }

    /// The board matches dots between layouts by id, so a duplicate within
    /// one result would make two dots fight over a single identity.
    func testIdsAreUniqueWithinEachMode() {
        let noteDots = DetectionBoardAdapter.dots(mode: .notes, note: d3, positions: positions(for: d3.midiNote), chord: nil)
        XCTAssertEqual(Set(noteDots.map(\.id)).count, noteDots.count)

        let chord = ChordMatch(root: "E", quality: .major, confidence: 1)
        let chordDots = DetectionBoardAdapter.dots(mode: .chords, note: nil, positions: [], chord: chord)
        XCTAssertEqual(Set(chordDots.map(\.id)).count, chordDots.count)
    }
}
