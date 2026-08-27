import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/Chords.svelte`.
///
/// A chord shape is only worth showing if it really is that chord, so the
/// central assertions are that every sounded string carries a degree the
/// formula contains, and that the degree labels are derived rather than
/// decorative.
@MainActor
final class ChordsModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel() -> (ChordsModuleModel, Heard) {
        let heard = Heard()
        let model = ChordsModuleModel { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - The chord is the chord

    /// Every sounded string must contribute a degree the formula actually has.
    /// A `?` here means the shape contains a note the chord does not.
    func testEverySoundedStringCarriesADegreeOfTheChord() {
        let (model, _) = makeModel()
        for formula in ChordFormulas.all {
            model.selectFormula(formula)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                for voicing in model.voicings {
                    model.selectPosition(id: voicing.id)
                    for dot in model.dots {
                        XCTAssertNotEqual(dot.label, "?",
                                          "\(PitchClass(root).name())\(formula.suffix) \(voicing.id) has a note outside the chord")
                        XCTAssertTrue(formula.degrees.contains(dot.label),
                                      "\(dot.label) is not a degree of \(formula.label)")
                    }
                }
            }
        }
    }

    /// The pitch classes on the board must be exactly the chord's — the same
    /// check from the other direction.
    func testEveryVoicingSoundsTheChordsPitchClasses() {
        let (model, _) = makeModel()
        for formula in ChordFormulas.all {
            model.selectFormula(formula)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                let allowed = Set(formula.intervals.map { PitchClass(root + $0).value })
                for voicing in model.voicings {
                    model.selectPosition(id: voicing.id)
                    for dot in model.dots {
                        let midi = Tunings.standard.openMIDINotes[dot.position.string] + dot.position.fret
                        XCTAssertTrue(allowed.contains(PitchClass(midi).value),
                                      "\(PitchClass(root).name())\(formula.suffix) sounds a note outside the chord")
                    }
                }
            }
        }
    }

    /// Every shape must contain its root, or the chord has no anchor to be
    /// read from.
    func testEveryVoicingContainsItsRoot() {
        let (model, _) = makeModel()
        for formula in ChordFormulas.all {
            model.selectFormula(formula)
            for voicing in model.voicings {
                model.selectPosition(id: voicing.id)
                XCTAssertTrue(model.dots.contains { $0.label == "1" },
                              "\(formula.label) \(voicing.id) has no root")
            }
        }
    }

    func testAPowerChordHasNoThird() {
        let (model, _) = makeModel()
        model.selectFormula(ChordFormulas.formula(id: "power")!)
        for voicing in model.voicings {
            model.selectPosition(id: voicing.id)
            let degrees = Set(model.dots.map(\.label))
            XCTAssertEqual(degrees, ["1", "5"], "a power chord is root and fifth only")
        }
    }

    func testMinorAndMajorDifferOnlyInTheThird() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectFormula(ChordFormulas.formula(id: "maj")!)
        let major = Set(model.dots.map(\.label))
        model.selectFormula(ChordFormulas.formula(id: "min")!)
        let minor = Set(model.dots.map(\.label))
        XCTAssertTrue(major.contains("3"))
        XCTAssertTrue(minor.contains("b3"))
        XCTAssertEqual(major.subtracting(["3"]), minor.subtracting(["b3"]))
    }

    // MARK: - Muted strings

    /// A shape that mutes a string must say so. A diagram that silently omits
    /// them teaches a chord you cannot actually strum.
    func testMutedStringsAreReportedAndNotDrawn() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectFormula(ChordFormulas.formula(id: "maj")!)

        guard let voicing = model.currentVoicing else { return XCTFail("no voicing") }
        let mutedFromVoicing = voicing.frets.enumerated().compactMap { $1 == nil ? $0 : nil }
        XCTAssertEqual(model.mutedStrings, mutedFromVoicing)
        for string in model.mutedStrings {
            XCTAssertNil(model.dots.first { $0.position.string == string },
                         "string \(string) is muted but drawn")
        }
    }

    func testStrummingSkipsMutedStrings() {
        let (model, heard) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectFormula(ChordFormulas.formula(id: "maj")!)
        let muted = Set(model.mutedStrings)
        model.strum()

        let settled = expectation(description: "strum")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        XCTAssertFalse(heard.positions.isEmpty)
        for position in heard.positions {
            XCTAssertFalse(muted.contains(position.string), "strummed a muted string")
        }
    }

    // MARK: - The two-level selector

    func testEveryFamilyHasFormulasAndSwitchingLandsInside() {
        let (model, _) = makeModel()
        for family in ChordsModuleModel.families {
            model.selectFamily(family)
            XCTAssertEqual(model.family, family)
            XCTAssertFalse(model.formulasInFamily.isEmpty, "\(family) has no formulas")
            XCTAssertTrue(model.formulasInFamily.contains { $0.id == model.formula.id },
                          "the selected formula is not in its own family")
        }
    }

    func testEveryFormulaIsReachableThroughItsFamily() {
        let (model, _) = makeModel()
        for formula in ChordFormulas.all {
            model.selectFamily(formula.family)
            XCTAssertTrue(model.formulasInFamily.contains { $0.id == formula.id },
                          "\(formula.label) is unreachable from \(formula.family)")
        }
    }

    func testTheSymbolReadsAsAChordIsWritten() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectFormula(ChordFormulas.formula(id: "maj")!)
        XCTAssertEqual(model.symbol, "C")
        model.selectFormula(ChordFormulas.formula(id: "min")!)
        XCTAssertEqual(model.symbol, "Cm")
        model.selectFormula(ChordFormulas.formula(id: "power")!)
        XCTAssertEqual(model.symbol, "C5")
        model.selectFormula(ChordFormulas.formula(id: "maj7")!)
        XCTAssertEqual(model.symbol, "Cmaj7")
    }

    // MARK: - Positions

    /// A saved position belongs to the previous root or formula, so changing
    /// either must land on a real shape rather than an index into a list that
    /// has changed length.
    func testChangingRootOrFormulaSnapsToARealPosition() {
        let (model, _) = makeModel()
        for formula in ChordFormulas.all {
            model.selectFormula(formula)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                guard !model.voicings.isEmpty else { continue }
                XCTAssertNotNil(model.currentVoicing)
                XCTAssertTrue(model.voicings.contains { $0.id == model.positionID },
                              "\(PitchClass(root).name())\(formula.suffix) landed on a position that does not exist")
            }
        }
    }

    func testMovingPositionWrapsThroughTheShapes() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectFormula(ChordFormulas.formula(id: "maj")!)
        let count = model.voicings.count
        guard count > 1 else { return }

        let start = model.positionIndex!
        model.movePosition(by: 1)
        XCTAssertEqual(model.positionIndex, (start + 1) % count)
        for _ in 0..<count { model.movePosition(by: 1) }
        XCTAssertEqual(model.positionIndex, (start + 1) % count)
    }

    func testEveryVoicingStaysOnTheModulesFifteenFretBoard() {
        let (model, _) = makeModel()
        for formula in ChordFormulas.all {
            model.selectFormula(formula)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                for voicing in model.voicings {
                    for fret in voicing.frets.compactMap({ $0 }) {
                        XCTAssertGreaterThanOrEqual(fret, 0)
                        XCTAssertLessThanOrEqual(fret, LearningModule.chords.highestFret,
                                                 "\(formula.label) \(voicing.id) runs past the board")
                    }
                }
            }
        }
    }

    func testThePositionLabelDescribesWhereTheHandGoes() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectFormula(ChordFormulas.formula(id: "maj")!)
        guard let voicing = model.currentVoicing else { return XCTFail("no voicing") }
        if voicing.isOpen {
            XCTAssertEqual(model.positionLabel, "Open")
        } else {
            XCTAssertTrue(model.positionLabel.hasPrefix("Fret"), model.positionLabel)
        }
    }

    // MARK: - Persistence

    func testTheSelectionIsPersistedAndRestored() {
        let storage = MemoryStorage()
        let model = ChordsModuleModel(store: PracticeStateStore(storage: storage))
        model.selectRoot(PitchClass(7))
        model.selectFormula(ChordFormulas.formula(id: "m7")!)
        model.movePosition(by: 1)

        let restored = ChordsModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.rootPitchClass.value, 7)
        XCTAssertEqual(restored.formula.id, "m7")
        XCTAssertEqual(restored.positionID, model.positionID)
    }

    func testAnUnknownSavedFormulaFallsBack() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"chords":{"rootPitchClass":3,"formulaID":"nope","positionID":"x"}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.chords.formulaID, "maj")
        XCTAssertEqual(decoded.modules.chords.rootPitchClass, 3, "and must not take the rest with it")
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
