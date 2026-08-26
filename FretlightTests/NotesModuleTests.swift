import XCTest
@testable import Fretwork

/// Ported from the Notes module's behaviour in
/// `../fretwork/src/lib/modules/Notes.svelte`.
///
/// The module's whole idea is that two ways of editing the board produce one
/// set of dots, so most of these assert that the note buttons and the taps
/// cannot disagree.
@MainActor
final class NotesModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel(tuning: Tuning = Tunings.standard) -> (NotesModuleModel, Heard) {
        let heard = Heard()
        let model = NotesModuleModel(tuning: tuning) { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - Opening state

    /// The web opens with every C on the neck. A board that starts empty
    /// teaches nothing on arrival.
    func testTheBoardOpensWithEveryCOnTheNeck() {
        let (model, _) = makeModel()
        XCTAssertFalse(model.placed.isEmpty)
        for key in model.placed {
            let position = try? XCTUnwrap(model.position(forKey: key))
            XCTAssertEqual(model.pitchClass(at: position!).value, 0, "\(key) is not a C")
        }
        XCTAssertTrue(model.isNoteActive(PitchClass(0)))
    }

    func testTheDefaultBoardStaysWithinTheModulesFretCeiling() {
        let (model, _) = makeModel()
        for key in model.placed {
            let position = model.position(forKey: key)
            XCTAssertNotNil(position, "\(key) is off this module's board")
            XCTAssertLessThanOrEqual(position!.fret, LearningModule.notes.highestFret)
        }
    }

    // MARK: - Note buttons

    /// The rule the web states: a button is on only when *every* position of
    /// that note is present, so the button can never claim more than the board
    /// shows.
    func testANoteButtonIsLitOnlyWhenEveryPositionIsPlaced() {
        let (model, _) = makeModel()
        let c = PitchClass(0)
        XCTAssertTrue(model.isNoteActive(c))

        // Remove a single C and the button must go dark.
        let key = model.placed.first { model.pitchClass(at: model.position(forKey: $0)!).value == 0 }!
        let position = model.position(forKey: key)!
        model.longPressCell(string: position.string, fret: position.fret)
        XCTAssertFalse(model.isNoteActive(c), "one missing position must unlight the button")
    }

    func testTogglingANoteOnPlacesEveryPositionOfIt() {
        let (model, _) = makeModel()
        let g = PitchClass(7)
        XCTAssertFalse(model.isNoteActive(g))
        model.toggleNote(g)
        XCTAssertTrue(model.isNoteActive(g))

        let expected = Positions.findAll(pitchClasses: [g], fretCount: LearningModule.notes.highestFret).count
        let actual = model.placed.filter { model.pitchClass(at: model.position(forKey: $0)!).value == 7 }.count
        XCTAssertEqual(actual, expected)
    }

    func testTogglingANoteOffRemovesOnlyThatNote() {
        let (model, _) = makeModel()
        model.toggleNote(PitchClass(7))
        let before = model.placed.count
        model.toggleNote(PitchClass(7))
        XCTAssertFalse(model.isNoteActive(PitchClass(7)))
        XCTAssertTrue(model.isNoteActive(PitchClass(0)), "the Cs must survive")
        XCTAssertLessThan(model.placed.count, before)
    }

    /// Placing a note by tapping and then toggling its button must not leave
    /// two entries for one position — the set is deduplicated by position, and
    /// duplicate dots would render on top of each other.
    func testPlacingByTapThenByButtonLeavesNoDuplicates() {
        let (model, _) = makeModel()
        model.tapCell(string: 0, fret: 3) // a G
        model.toggleNote(PitchClass(7))
        XCTAssertEqual(Set(model.placed).count, model.placed.count, "duplicate keys: \(model.placed)")
        XCTAssertEqual(Set(model.dots.map(\.id)).count, model.dots.count, "duplicate dot ids")
    }

    // MARK: - Taps

    func testTappingAnEmptyCellPlacesAndSoundsThatNote() {
        let (model, heard) = makeModel()
        let before = model.placed.count
        model.tapCell(string: 2, fret: 5)
        XCTAssertEqual(model.placed.count, before + 1)
        XCTAssertTrue(model.placed.contains("2:5"))
        XCTAssertEqual(heard.positions.last, FretPosition(string: 2, fret: 5))
    }

    func testTappingAnExistingDotSoundsItWithoutAddingAnother() {
        let (model, heard) = makeModel()
        model.tapCell(string: 2, fret: 5)
        let after = model.placed.count
        model.tapCell(string: 2, fret: 5)
        XCTAssertEqual(model.placed.count, after, "a second tap must not add a duplicate")
        XCTAssertEqual(heard.positions.count, 2, "but it must sound again")
    }

    func testLongPressRemovesOnlyThatPosition() {
        let (model, _) = makeModel()
        model.tapCell(string: 2, fret: 5)
        model.tapCell(string: 3, fret: 5)
        model.longPressCell(string: 2, fret: 5)
        XCTAssertFalse(model.placed.contains("2:5"))
        XCTAssertTrue(model.placed.contains("3:5"))
    }

    func testClearAllEmptiesTheBoard() {
        let (model, _) = makeModel()
        model.clearAll()
        XCTAssertTrue(model.placed.isEmpty)
        XCTAssertTrue(model.dots.isEmpty)
        XCTAssertEqual(model.chordLabel, "—")
    }

    // MARK: - Derived readout

    func testChordDiscoveryNamesWhatIsOnTheBoard() {
        let (model, _) = makeModel()
        model.clearAll()
        // C major triad: C, E, G.
        model.tapCell(string: 1, fret: 3)  // C
        model.tapCell(string: 0, fret: 0)  // E
        model.tapCell(string: 0, fret: 3)  // G
        XCTAssertEqual(model.discovery.primary?.symbol, "C")
        XCTAssertEqual(model.present.map { $0.pitchClass.name() }, ["C", "E", "G"])
    }

    func testAnEmptyBoardReportsNoChordRatherThanGuessing() {
        let (model, _) = makeModel()
        model.clearAll()
        XCTAssertNil(model.discovery.primary)
        XCTAssertEqual(model.discovery.status, .empty)
    }

    func testEnharmonicHintsAppearOnlyForNotesThatHaveTwoNames() {
        let (model, _) = makeModel()
        model.clearAll()
        model.tapCell(string: 0, fret: 0) // E — one name
        XCTAssertTrue(model.enharmonicHints.isEmpty)
        model.tapCell(string: 0, fret: 2) // F♯
        XCTAssertEqual(model.enharmonicHints, ["F♯ = G♭"])
    }

    func testPresentCountsEveryOccurrenceButListsEachNoteOnce() {
        let (model, _) = makeModel()
        let cs = model.present.first { $0.pitchClass.value == 0 }
        XCTAssertEqual(model.present.filter { $0.pitchClass.value == 0 }.count, 1, "one entry per note")
        XCTAssertGreaterThan(cs?.count ?? 0, 1, "counting every C on the neck")
    }

    // MARK: - Dots

    /// `FretboardDot`'s docstring records why: an id derived from content turns
    /// a slide into a cross-fade.
    func testDotIdsDependOnPositionOnlyNotOnTuning() {
        let (standard, _) = makeModel()
        let ids = standard.dots.map(\.id).sorted()

        let (dropD, _) = makeModel(tuning: Tunings.dropD)
        // Same placed keys, different tuning: the notes change, the ids do not.
        XCTAssertEqual(Set(dropD.dots.map(\.id)).isSubset(of: Set(ids)), true)
    }

    /// A tuning change re-pitches the board, because a position's note depends
    /// on the string it is on.
    func testChangingTuningRepitchesTheBoardWithoutMovingDots() {
        let (model, _) = makeModel()
        model.clearAll()
        model.tapCell(string: 0, fret: 0)
        XCTAssertEqual(model.dots.first?.label, "E")

        model.tuning = Tunings.dropD
        XCTAssertEqual(model.dots.first?.label, "D", "the low string is now a D")
        XCTAssertEqual(model.dots.first?.position, FretPosition(string: 0, fret: 0), "but the dot has not moved")
    }

    // MARK: - Persistence

    func testTheBoardIsPersistedAndRestored() {
        let storage = MemoryStorage()
        let model = NotesModuleModel(store: PracticeStateStore(storage: storage))
        model.clearAll()
        model.tapCell(string: 4, fret: 7)

        // A second store over the same storage is what a relaunch looks like.
        let restored = NotesModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.placed, ["4:7"])
    }

    /// An empty board is a real state a player can choose, and it has to
    /// survive a relaunch rather than being mistaken for "never set" and
    /// refilled with the default Cs.
    func testAnEmptyBoardSurvivesARelaunch() {
        let storage = MemoryStorage()
        let model = NotesModuleModel(store: PracticeStateStore(storage: storage))
        model.clearAll()

        let restored = NotesModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertTrue(restored.placed.isEmpty, "the cleared board came back as \(restored.placed)")
    }
}


/// Storage that lives only for the test, so nothing writes into a real defaults
/// domain.
private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
