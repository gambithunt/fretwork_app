import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/Intervals.svelte`.
///
/// The module teaches that an interval is a shape under the hand, so most of
/// these assert on *where* the shape lands and on it staying valid when the
/// root, interval or tuning changes underneath it.
@MainActor
final class IntervalsModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel(tuning: Tuning = Tunings.standard) -> (IntervalsModuleModel, Heard) {
        let heard = Heard()
        let model = IntervalsModuleModel(tuning: tuning) { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - The interval itself

    func testTheTargetIsTheRootTransposedByTheInterval() {
        let (model, _) = makeModel()
        for interval in Intervals.all {
            model.selectInterval(interval)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                XCTAssertEqual(
                    model.targetPitchClass.value,
                    (root + interval.semitones) % 12,
                    "\(interval.short) from \(PitchClass(root).name())"
                )
            }
        }
    }

    /// Every target the board marks must genuinely be the interval away from
    /// the anchored root — in pitch, not just in pitch class, since the module
    /// is about a physical distance.
    func testEveryMarkedTargetIsExactlyTheIntervalAboveTheRoot() {
        let (model, _) = makeModel()
        for interval in Intervals.all {
            model.selectInterval(interval)
            guard let anchor = model.activeAnchor else { continue }
            for target in anchor.targets {
                XCTAssertEqual(
                    target.midiNote - anchor.root.midiNote,
                    interval.semitones,
                    "\(interval.short) target at \(target.string):\(target.fret)"
                )
            }
        }
    }

    func testTheExerciseNamesTheActualNotes() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectInterval(Intervals.all.first { $0.short == "P5" }!)
        XCTAssertTrue(model.exercise.contains("C"), model.exercise)
        XCTAssertTrue(model.exercise.contains("G"), model.exercise)
        XCTAssertFalse(model.exercise.contains("{root}"))
        XCTAssertFalse(model.exercise.contains("{target}"))
    }

    // MARK: - Anchoring

    func testTappingARootAnchorsThereWhenItIsPlayable() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        let target = model.playableAnchors.last!
        model.selectAnchor(string: target.root.string, fret: target.root.fret)
        XCTAssertEqual(model.activeAnchor.map { IntervalsModuleModel.key($0.root) },
                       IntervalsModuleModel.key(target.root))
    }

    /// Tapping somewhere with no root snaps to the nearest playable anchor
    /// rather than blanking the board.
    func testTappingAwayFromAnyRootSnapsToTheNearestPlayableAnchor() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectAnchor(string: 5, fret: 11)
        XCTAssertNotNil(model.activeAnchor, "the board must keep showing a real shape")
        XCTAssertTrue(model.activeAnchor!.isPlayable)
    }

    /// A saved anchor can become unreachable when the root or interval changes.
    /// Re-anchoring is what keeps the board from going blank.
    func testChangingRootKeepsAValidAnchor() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            let anchor = model.activeAnchor
            XCTAssertNotNil(anchor, "no anchor for root \(PitchClass(root).name())")
            XCTAssertEqual(anchor?.root.pitchClass.value, root, "anchored on the wrong note")
            XCTAssertTrue(anchor?.isPlayable ?? false)
        }
    }

    func testChangingIntervalKeepsAValidAnchor() {
        let (model, _) = makeModel()
        for interval in Intervals.all {
            model.selectInterval(interval)
            XCTAssertNotNil(model.activeAnchor, "no anchor for \(interval.short)")
            XCTAssertTrue(model.activeAnchor?.isPlayable ?? false, "\(interval.short) anchored somewhere unplayable")
        }
    }

    func testChangingTuningRepitchesAndReanchors() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(2))
        model.retune(to: Tunings.dropD)
        guard let anchor = model.activeAnchor else { return XCTFail("no anchor after retune") }
        XCTAssertEqual(anchor.root.pitchClass.value, 2, "the anchor must still be on the chosen root")
        XCTAssertEqual(Tunings.dropD.openMIDINotes[anchor.root.string] + anchor.root.fret, anchor.root.midiNote,
                       "the anchor's pitch must be derived from the new tuning")
    }

    // MARK: - The practical target

    /// The closest target, counting a string change as worth two frets. It is
    /// what the module suggests you actually play.
    func testThePracticalTargetIsTheClosestOneToTheRoot() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectInterval(Intervals.all.first { $0.short == "P5" }!)
        guard let anchor = model.activeAnchor, let practical = model.practicalTarget else {
            return XCTFail("no target")
        }
        func reach(_ target: NeckPosition) -> Int {
            abs(target.fret - anchor.root.fret) + abs(target.string - anchor.root.string) * 2
        }
        for target in anchor.targets {
            XCTAssertLessThanOrEqual(reach(practical), reach(target))
        }
    }

    // MARK: - Dots

    func testTheAnchoredRootAndItsTargetsAreDrawnFullSize() {
        let (model, _) = makeModel()
        guard let anchor = model.activeAnchor else { return XCTFail("no anchor") }
        let rootDot = model.dots.first { $0.id == "root-\(IntervalsModuleModel.key(anchor.root))" }
        XCTAssertNotNil(rootDot)
        XCTAssertEqual(rootDot?.radius, FretboardDot.defaultRadius)
        XCTAssertEqual(rootDot?.alpha, 1)

        for target in anchor.targets {
            XCTAssertNotNil(model.dots.first { $0.id == "target-\(IntervalsModuleModel.key(target))" },
                            "target \(target.string):\(target.fret) is not on the board")
        }
    }

    /// The other roots are context, not content — recessed so the chosen shape
    /// reads as the subject.
    func testUnchosenRootsAreRecessed() {
        let (model, _) = makeModel()
        let options = model.dots.filter { $0.id.hasPrefix("root-option-") }
        XCTAssertFalse(options.isEmpty)
        for dot in options {
            XCTAssertLessThan(dot.radius, FretboardDot.defaultRadius)
            XCTAssertLessThan(dot.alpha, 1)
        }
    }

    func testNoPositionIsDrawnTwice() {
        let (model, _) = makeModel()
        for interval in Intervals.all {
            model.selectInterval(interval)
            let positions = model.dots.map { "\($0.position.string):\($0.position.fret)" }
            XCTAssertEqual(Set(positions).count, positions.count,
                           "\(interval.short) draws two dots on one position")
            XCTAssertEqual(Set(model.dots.map(\.id)).count, model.dots.count, "duplicate dot ids")
        }
    }

    func testEveryDotStaysOnTheModulesBoard() {
        let (model, _) = makeModel()
        for interval in Intervals.all {
            model.selectInterval(interval)
            for dot in model.dots {
                XCTAssertLessThanOrEqual(dot.position.fret, LearningModule.intervals.highestFret,
                                         "\(interval.short) drew past the board")
                XCTAssertGreaterThanOrEqual(dot.position.fret, 0)
            }
        }
    }

    // MARK: - Persistence

    func testTheSelectionIsPersistedAndRestored() {
        let storage = MemoryStorage()
        let model = IntervalsModuleModel(store: PracticeStateStore(storage: storage))
        model.selectRoot(PitchClass(9))
        model.selectInterval(Intervals.all.first { $0.short == "m3" }!)

        let restored = IntervalsModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.rootPitchClass.value, 9)
        XCTAssertEqual(restored.interval.short, "m3")
        XCTAssertEqual(restored.anchorKey, model.anchorKey)
    }

    /// A retired interval name must fall back rather than leaving the module
    /// pointing at nothing — the same field-by-field defaulting the rest of the
    /// document uses.
    func testAnUnknownSavedIntervalFallsBack() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"intervals":{"rootPitchClass":3,"intervalShort":"P57","anchor":"2:4"}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.intervals.intervalShort, "P5", "unknown interval must fall back")
        XCTAssertEqual(decoded.modules.intervals.rootPitchClass, 3, "and must not take the rest with it")
        XCTAssertEqual(decoded.modules.intervals.anchor, "2:4")
    }

    // MARK: - Playback

    func testPlayingSoundsTheRootAndTheTarget() {
        let (model, heard) = makeModel()
        model.selectRoot(PitchClass(0))
        model.playInterval()

        let expectation = XCTestExpectation(description: "notes sound")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertFalse(heard.positions.isEmpty, "nothing sounded")
    }

    func testStoppingClearsThePulses() {
        let (model, _) = makeModel()
        model.playInterval()
        model.stop()
        XCTAssertTrue(model.pulses.isEmpty)
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
