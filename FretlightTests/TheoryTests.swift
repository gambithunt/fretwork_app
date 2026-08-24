import XCTest
@testable import Fretwork

final class TheoryTests: XCTestCase {
    func testPitchClassNormalizesOutOfRangeValues() {
        XCTAssertEqual(PitchClass(-1).value, 11)
        XCTAssertEqual(PitchClass(-25).value, 11)
        XCTAssertEqual(PitchClass(12).value, 0)
        XCTAssertEqual(PitchClass(37).value, 1)
    }

    func testTransposingWrapsPastB() {
        XCTAssertEqual(PitchClass(11).transposed(by: 1), PitchClass(0))
        XCTAssertEqual(PitchClass(0).transposed(by: -1), PitchClass(11))
        XCTAssertEqual(PitchClass(4).transposed(by: 12), PitchClass(4))
    }

    func testNoteNameStylesCoverChromaticScale() {
        XCTAssertEqual(PitchClass.chromatic.map { $0.name() },
                       ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"])
        XCTAssertEqual(PitchClass.chromatic.map { $0.name(.flat) },
                       ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"])
    }

    func testEnharmonicAliasesOnlyExistForAccidentals() {
        XCTAssertNil(PitchClass(0).enharmonicAlias)
        XCTAssertNil(PitchClass(4).enharmonicAlias)
        XCTAssertEqual(PitchClass(1).enharmonicAlias, "D♭")
        XCTAssertEqual(PitchClass(10).enharmonicAlias, "B♭")
    }

    func testTheoryCataloguesHaveExpectedEntries() {
        XCTAssertEqual(Intervals.all.count, 12)
        XCTAssertEqual(Scales.all.count, 6)
        XCTAssertEqual(Triads.all.count, 4)
        XCTAssertEqual(ChordFormulas.all.count, 16)
        XCTAssertTrue(ChordFormulas.all.allSatisfy { $0.intervals.count == $0.degrees.count })
        XCTAssertTrue(Scales.all.allSatisfy { $0.intervals.count == $0.degrees.count })
        XCTAssertTrue(Intervals.all.allSatisfy { !$0.uses.isEmpty })
    }

    /// The catalogue is an array precisely so this order is fixed; a dictionary
    /// would let a UI listing scales reshuffle them between launches.
    func testScaleCatalogueOrderIsStable() {
        XCTAssertEqual(Scales.all.map(\.id),
                       ["major", "naturalMinor", "locrian", "lydianAugmented", "majorPentatonic", "minorPentatonic"])
        XCTAssertEqual(Scales.scale(id: "locrian"), Scales.locrian)
        XCTAssertNil(Scales.scale(id: "not-a-scale"))
    }

    func testChordFormulaLookupPreservesSpellingOrder() {
        XCTAssertEqual(ChordFormulas.formula(id: "add9")?.intervals, [0, 4, 7, 2])
        XCTAssertEqual(ChordFormulas.formula(id: "13")?.intervals, [0, 4, 7, 10, 9])
        XCTAssertNil(ChordFormulas.formula(id: "not-a-formula"))
    }

    func testSpellScalePreservesTheoryCorrectLetters() {
        XCTAssertEqual(Scales.major.spelled(from: PitchClass(6)),
                       ["F♯", "G♯", "A♯", "B", "C♯", "D♯", "E♯"])
        XCTAssertEqual(Scales.locrian.spelled(from: PitchClass(0)),
                       ["C", "D♭", "E♭", "F", "G♭", "A♭", "B♭"])
        XCTAssertEqual(Scales.major.spelled(from: PitchClass(0)),
                       ["C", "D", "E", "F", "G", "A", "B"])
    }

    func testNoteMapperRetainsSharpPitchClassNames() {
        XCTAssertEqual(NoteMapper.pitchClassNames,
                       ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"])
    }
}
