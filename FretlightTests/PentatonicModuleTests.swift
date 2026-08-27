import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/Pentatonic.svelte`.
///
/// Two things carry the module: the boxes must actually be the scale, and the
/// multi-box views must fit on the neck. `CLAUDE.md` records that the
/// tuning-parameterisation mistake slipped into this generator twice, so the
/// scale-membership assertions are the ones to keep.
@MainActor
final class PentatonicModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel() -> (PentatonicModuleModel, Heard) {
        let heard = Heard()
        let model = PentatonicModuleModel { heard.positions.append($0) }
        return (model, heard)
    }

    /// The five pitch classes of the scale, derived independently of the shape
    /// generator so this is a real cross-check rather than a restatement.
    private func expectedPitchClasses(root: Int, quality: PentatonicQuality) -> Set<Int> {
        let intervals = quality == .minorPentatonic ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9]
        return Set(intervals.map { PitchClass(root + $0).value })
    }

    // MARK: - The boxes are the scale

    func testEveryBoxContainsOnlyScaleNotes() {
        let (model, _) = makeModel()
        for quality in [PentatonicQuality.minorPentatonic, .majorPentatonic] {
            model.selectQuality(quality)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                let allowed = expectedPitchClasses(root: root, quality: quality)
                for box in 0...4 {
                    model.selectPosition(box)
                    XCTAssertFalse(model.box.isEmpty, "box \(box) is empty")
                    for step in model.box {
                        XCTAssertTrue(allowed.contains(step.pitchClass.value),
                                      "\(PitchClass(root).name()) \(quality.rawValue) box \(box) has \(step.pitchClass.name())")
                    }
                }
            }
        }
    }

    /// A pentatonic box is two notes per string across all six.
    func testEveryBoxIsTwoNotesPerString() {
        let (model, _) = makeModel()
        for box in 0...4 {
            model.selectPosition(box)
            var perString: [Int: Int] = [:]
            for step in model.box { perString[step.string, default: 0] += 1 }
            XCTAssertEqual(perString.count, 6, "box \(box) does not cover all six strings")
            for (string, count) in perString {
                XCTAssertEqual(count, 2, "box \(box) has \(count) notes on string \(string)")
            }
        }
    }

    /// Between them the five boxes must cover the whole scale — otherwise a
    /// note of the scale would be unreachable from any position.
    func testTheFiveBoxesTogetherCoverEveryScaleNote() {
        let (model, _) = makeModel()
        for quality in [PentatonicQuality.minorPentatonic, .majorPentatonic] {
            model.selectQuality(quality)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                var seen: Set<Int> = []
                for box in 0...4 {
                    model.selectPosition(box)
                    seen.formUnion(model.box.map(\.pitchClass.value))
                }
                XCTAssertEqual(seen, expectedPitchClasses(root: root, quality: quality),
                               "\(PitchClass(root).name()) \(quality.rawValue) is not fully covered")
            }
        }
    }

    func testEveryBoxStaysOnTheModulesFifteenFretBoard() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            for box in 0...4 {
                model.selectPosition(box)
                for step in model.box {
                    XCTAssertGreaterThanOrEqual(step.fret, 0)
                    XCTAssertLessThanOrEqual(step.fret, LearningModule.pentatonic.highestFret,
                                             "box \(box) runs past the board")
                }
            }
        }
    }

    /// The relative-minor relationship: A minor pentatonic and C major
    /// pentatonic are the same five notes.
    func testARelativeMajorAndMinorShareTheirNotes() {
        let (model, _) = makeModel()
        model.selectQuality(.minorPentatonic)
        model.selectRoot(PitchClass(9))
        model.selectPosition(0)
        let minor = Set(model.box.map(\.pitchClass.value))

        model.selectQuality(.majorPentatonic)
        model.selectRoot(PitchClass(0))
        model.selectPosition(0)
        let major = Set(model.box.map(\.pitchClass.value))

        XCTAssertEqual(minor, major, "A minor and C major pentatonic are the same notes")
    }

    // MARK: - Display modes

    /// A pair or path must fit inside 1...5, or it would silently show fewer
    /// boxes than it claims.
    func testPairAndPathAlwaysFitOnTheNeck() {
        let (model, _) = makeModel()
        for box in 0...4 {
            model.selectPosition(box)
            model.selectDisplayMode(.pair)
            XCTAssertEqual(model.visiblePositions.count, 2, "pair at box \(box)")
            model.selectDisplayMode(.path)
            XCTAssertEqual(model.visiblePositions.count, 3, "path at box \(box)")
            for position in model.visiblePositions {
                XCTAssertTrue((0...4).contains(position))
            }
        }
    }

    /// In a path the focus is the middle box, so the player can see where the
    /// shape came from and where it goes.
    func testAPathFocusesTheMiddleBox() {
        let (model, _) = makeModel()
        model.selectPosition(2)
        model.selectDisplayMode(.path)
        XCTAssertEqual(model.visiblePositions, [1, 2, 3])
        XCTAssertEqual(model.focusPosition, 2)
    }

    /// Neighbours are context: recessed and unlabelled, so the focus box reads
    /// as the subject rather than the neck being a wall of dots.
    func testNeighbouringBoxesAreRecessedAndUnlabelled() {
        let (model, _) = makeModel()
        model.selectPosition(2)
        model.selectDisplayMode(.path)

        let context = model.dots.filter { $0.id.hasPrefix("pent-context-") }
        XCTAssertFalse(context.isEmpty)
        for dot in context {
            XCTAssertEqual(dot.label, "")
            XCTAssertLessThan(dot.radius, FretboardDot.defaultRadius)
            XCTAssertLessThan(dot.alpha, 1)
        }
        let focus = model.dots.filter { !$0.id.hasPrefix("pent-context-") }
        XCTAssertEqual(focus.count, model.box.count)
        for dot in focus { XCTAssertEqual(dot.alpha, 1) }
    }

    func testSingleModeShowsOnlyTheChosenBox() {
        let (model, _) = makeModel()
        model.selectPosition(1)
        model.selectDisplayMode(.single)
        XCTAssertEqual(model.visiblePositions, [1])
        XCTAssertTrue(model.dots.allSatisfy { !$0.id.hasPrefix("pent-context-") })
    }

    // MARK: - Guided practice

    func testGuidedPracticeCountsInThenWalksTheBox() {
        let (model, _) = makeModel()
        model.selectPosition(0)
        model.startGuided()

        XCTAssertEqual(model.guidedSnapshot.status, .countIn)
        XCTAssertEqual(model.guidedSnapshot.countInBeat, 1, "the count-in must show immediately")
        XCTAssertEqual(model.guidedSnapshot.total, model.box.count)
        XCTAssertNil(model.currentStep, "nothing sounds during the count-in")

        model.stopGuided()
        XCTAssertEqual(model.guidedSnapshot.status, .idle)
        XCTAssertNil(model.currentStep)
    }

    /// A run left going after the scale changed would be practising the old
    /// scale against the new shape.
    func testChangingAnythingStopsTheRun() {
        let (model, _) = makeModel()
        for change in [
            { model.selectRoot(PitchClass(5)) },
            { model.selectQuality(.majorPentatonic) },
            { model.selectPosition(3) },
            { model.selectDisplayMode(.pair) }
        ] {
            model.startGuided()
            XCTAssertNotEqual(model.guidedSnapshot.status, .idle)
            change()
            XCTAssertEqual(model.guidedSnapshot.status, .idle, "a selection change must stop the run")
        }
    }

    func testTempoMovesThroughThePresets() {
        let (model, _) = makeModel()
        model.startGuided()
        XCTAssertEqual(model.guidedSnapshot.tempoBpm, 80)
        XCTAssertEqual(model.slower(), 60)
        XCTAssertEqual(model.faster(), 80)
        model.stopGuided()
    }

    // MARK: - Persistence

    func testTheSelectionIsPersistedAndRestored() {
        let storage = MemoryStorage()
        let model = PentatonicModuleModel(store: PracticeStateStore(storage: storage))
        model.selectRoot(PitchClass(4))
        model.selectQuality(.majorPentatonic)
        model.selectPosition(3)
        model.selectDisplayMode(.path)

        let restored = PentatonicModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.rootPitchClass.value, 4)
        XCTAssertEqual(restored.quality, .majorPentatonic)
        XCTAssertEqual(restored.position, 3)
        XCTAssertEqual(restored.displayMode, .path)
        XCTAssertEqual(restored.displayStart, model.displayStart)
    }

    /// Guided playback state stays transient, as the workstream requires.
    func testARunInProgressIsNotPersisted() {
        let storage = MemoryStorage()
        let model = PentatonicModuleModel(store: PracticeStateStore(storage: storage))
        model.startGuided()
        XCTAssertNotEqual(model.guidedSnapshot.status, .idle)

        let restored = PentatonicModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.guidedSnapshot.status, .idle)
        XCTAssertNil(restored.currentStep)
    }

    func testAnOutOfRangeSavedPositionIsClamped() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"pentatonic":{"rootPitchClass":2,"position":99,"displayMode":"wat"}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.pentatonic.position, 4)
        XCTAssertEqual(decoded.modules.pentatonic.displayMode, "single")
        XCTAssertEqual(decoded.modules.pentatonic.rootPitchClass, 2)
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
