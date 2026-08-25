import XCTest
@testable import Fretwork

final class ChordDiscoveryTests: XCTestCase {
    /// `(pitch class, MIDI note, string)` per note.
    private func notes(_ values: [(Int, Int, Int)]) -> [DiscoveredNote] {
        values.map { DiscoveredNote(pitchClass: PitchClass($0.0), midiNote: $0.1, string: $0.2) }
    }

    /// Voices a formula from a root with the root lowest, one note per string.
    private func voiced(root: PitchClass, formula: ChordDiscovery.Formula) -> [DiscoveredNote] {
        formula.intervals.enumerated().map { index, interval in
            DiscoveredNote(
                pitchClass: root.transposed(by: interval),
                midiNote: 40 + root.value + interval,
                string: index
            )
        }
    }

    /// Every formula at every root, recognised from its own pitch set.
    ///
    /// The root is deliberately placed in the bass. Several formulas share a
    /// pitch set — Am7 with C6, Cm6 with Am7b5, and dim7 with three other
    /// roots of itself — and the bass is the only thing that separates them.
    /// A test that voiced these in any other order would be asserting the
    /// tie-break rather than the recognition.
    func testEveryFormulaAtEveryRootIsRecognisedFromItsOwnPitchSet() {
        for formula in ChordDiscovery.formulas {
            for root in PitchClass.chromatic {
                let label = "\(root.name())\(formula.suffix)"
                let result = ChordDiscovery.discover(voiced(root: root, formula: formula))
                XCTAssertEqual(result.status, .match, label)
                XCTAssertTrue(result.playableVoicing, label)
                XCTAssertEqual(result.primary?.root, root, label)
                XCTAssertEqual(result.primary?.quality, formula.quality, label)
                XCTAssertEqual(result.primary?.symbol, root.name() + formula.suffix, label)
                XCTAssertNil(result.primary?.inversion, label)
                XCTAssertEqual(result.uniquePitchClasses.count, formula.intervals.count, label)
            }
        }
    }

    func testRepeatedPitchClassesDoNotPreventAnExactMatch() {
        let result = ChordDiscovery.discover(notes([(0, 48, 0), (4, 52, 1), (7, 55, 2), (0, 60, 3)]))
        XCTAssertEqual(result.status, .match)
        XCTAssertEqual(result.primary?.symbol, "C")
        XCTAssertEqual(result.primary?.quality, "Major")
        XCTAssertEqual(result.uniquePitchClasses.map(\.value), [0, 4, 7])
    }

    func testBassNoteDrivesSlashSymbolsAndInversionNames() {
        let first = ChordDiscovery.discover(notes([(4, 40, 0), (7, 43, 1), (0, 48, 2)]))
        XCTAssertEqual(first.primary?.symbol, "C/E")
        XCTAssertEqual(first.primary?.inversion, .first)
        XCTAssertTrue(first.message.contains("1st inversion"))

        let second = ChordDiscovery.discover(notes([(7, 43, 0), (0, 48, 1), (4, 52, 2)]))
        XCTAssertEqual(second.primary?.symbol, "C/G")
        XCTAssertEqual(second.primary?.inversion, .second)

        // A third inversion needs a fourth tone, so only the seventh chord
        // reaches it — a triad with its fifth lowest stops at second.
        let third = ChordDiscovery.discover(notes([(11, 47, 0), (0, 48, 1), (4, 52, 2), (7, 55, 3)]))
        XCTAssertEqual(third.primary?.symbol, "Cmaj7/B")
        XCTAssertEqual(third.primary?.inversion, .third)
    }

    func testSharedPitchSetsAreRankedByTheBassAndKeptAsAlternatives() {
        let result = ChordDiscovery.discover(notes([(9, 57, 0), (0, 60, 1), (4, 64, 2), (7, 67, 3)]))
        XCTAssertEqual(result.primary?.symbol, "Am7")
        XCTAssertTrue(result.alternatives.map(\.symbol).contains("C6/A"))
    }

    func testTwoNotesOnOneStringIsNotAPlayableVoicing() {
        let result = ChordDiscovery.discover(notes([(4, 40, 0), (0, 48, 0), (7, 55, 1)]))
        XCTAssertFalse(result.playableVoicing)
        XCTAssertEqual(result.primary?.symbol, "C")
        XCTAssertNil(result.primary?.inversion)
        XCTAssertTrue(result.message.contains("pitch-set match"))
    }

    func testTwoNoteFifthsReportAPowerChordRatherThanAQuality() {
        let result = ChordDiscovery.discover(notes([(2, 50, 0), (9, 57, 1)]))
        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.primary?.symbol, "D5")
        XCTAssertEqual(result.primary?.degrees, ["1", "5"])
        XCTAssertTrue(result.message.contains("no 3rd"))
    }

    func testEmptyInsufficientAndUnknownStates() {
        XCTAssertEqual(ChordDiscovery.discover([]).status, .empty)
        XCTAssertEqual(ChordDiscovery.discover(notes([(0, 48, 5)])).status, .insufficient)
        // Two notes that are not a fifth apart still cannot name a chord.
        XCTAssertEqual(ChordDiscovery.discover(notes([(0, 48, 5), (1, 49, 4)])).status, .insufficient)
        // Three chromatic neighbours match no formula at any root.
        XCTAssertEqual(ChordDiscovery.discover(notes([(0, 48, 5), (1, 49, 4), (6, 54, 3)])).status, .unknown)
    }

    func testNoteNamesUseTheAppsUnicodeAccidentals() {
        let result = ChordDiscovery.discover(notes([(1, 49, 0), (4, 52, 1), (8, 56, 2)]))
        XCTAssertEqual(result.primary?.symbol, "C♯m")
        XCTAssertEqual(result.primary?.degrees, ["1", "b3", "5"])
    }
}
