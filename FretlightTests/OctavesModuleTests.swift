import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/Octaves.svelte` and
/// `recall-challenge.ts`.
///
/// The module's claim is that the octave is a *movable shape*, so the tests
/// that matter are the ones about the shape staying true — especially across
/// the G–B string pair, where standard tuning's major-third gap makes the
/// offset three frets instead of two. A module that assumed +2 everywhere would
/// be wrong on a third of the neck and still look plausible.
@MainActor
final class OctavesModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel(tuning: Tuning = Tunings.standard) -> (OctavesModuleModel, Heard) {
        let heard = Heard()
        let model = OctavesModuleModel(tuning: tuning) { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - The shape

    /// The one that matters: every target must be exactly twelve semitones
    /// above its root, in pitch. Pitch class alone would accept a unison.
    func testEveryTargetIsExactlyOneOctaveAboveItsRoot() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            for shape in model.shapes {
                XCTAssertEqual(shape.target.midiNote - shape.root.midiNote, 12,
                               "\(PitchClass(root).name()) at \(shape.root.string):\(shape.root.fret)")
                XCTAssertEqual(shape.target.pitchClass.value, root)
            }
        }
    }

    func testTheShapeAlwaysSkipsExactlyOneString() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            for shape in model.shapes {
                XCTAssertEqual(shape.target.string - shape.root.string, 2,
                               "the octave shape is two strings up, always")
            }
        }
    }

    /// Standard tuning's G–B pair is a major third rather than a fourth, so a
    /// shape spanning it stretches by a fret. This is the exception the module
    /// exists to teach.
    ///
    /// The offsets are pinned as literals here because they are the *human*
    /// fact a player learns — two frets low down, three once the shape reaches
    /// the B string. A shape rooted on string s spans strings s to s+2, so it
    /// crosses the G–B step (strings 3 to 4) when s is 2 or 3.
    func testTheOffsetIsTwoFretsLowAndThreeAcrossTheGBPair() {
        let (model, _) = makeModel()
        let expected = [0: 2, 1: 2, 2: 3, 3: 3]
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            for shape in model.shapes {
                XCTAssertEqual(shape.fretOffset, expected[shape.root.string],
                               "root on string \(shape.root.string) fret \(shape.root.fret)")
            }
        }
    }

    /// And in any tuning the offset must equal what that tuning implies, which
    /// is the invariant behind the numbers above.
    func testTheOffsetIsDerivedFromTheTuningInEveryTuning() {
        for tuning in Tunings.all {
            let (model, _) = makeModel(tuning: tuning)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                for shape in model.shapes {
                    let implied = tuning.openMIDINotes[shape.root.string] + 12
                        - tuning.openMIDINotes[shape.target.string]
                    XCTAssertEqual(shape.fretOffset, implied,
                                   "\(tuning.name) string \(shape.root.string)")
                }
            }
        }
    }

    /// Drop D is the clearest case of the offset genuinely moving: the low
    /// string becomes a D, which is the same note the D string is already
    /// tuned to, so the octave lands at the *same fret* two strings up rather
    /// than two frets along. Assuming a fixed shape would put it two frets
    /// wrong on that string.
    func testDropDCollapsesTheLowStringShapeToNoFretOffset() {
        let (model, _) = makeModel(tuning: Tunings.dropD)
        model.selectRoot(PitchClass(2))
        let onLowString = model.shapes.filter { $0.root.string == 0 }
        XCTAssertFalse(onLowString.isEmpty)
        for shape in onLowString {
            XCTAssertEqual(shape.target.midiNote - shape.root.midiNote, 12)
            XCTAssertEqual(shape.fretOffset, 0)
            XCTAssertEqual(shape.target.fret, shape.root.fret)
        }
    }

    func testEveryShapeStaysOnTheModulesBoard() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            for shape in model.shapes {
                XCTAssertLessThanOrEqual(shape.target.fret, LearningModule.octaves.highestFret)
                XCTAssertGreaterThanOrEqual(shape.root.fret, 0)
            }
        }
    }

    // MARK: - Anchoring

    func testMovingTheAnchorStepsThroughTheShapesAndWraps() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        let count = model.shapes.count
        XCTAssertGreaterThan(count, 1)

        let start = model.anchoredIndex
        model.moveAnchor(by: 1)
        XCTAssertEqual(model.anchoredIndex, (start! + 1) % count)

        for _ in 0..<count { model.moveAnchor(by: 1) }
        XCTAssertEqual(model.anchoredIndex, (start! + 1) % count, "a full lap returns to the same shape")
    }

    func testChangingRootKeepsAValidAnchor() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            XCTAssertNotNil(model.anchoredShape, "no shape for \(PitchClass(root).name())")
            XCTAssertEqual(model.anchoredShape?.root.pitchClass.value, root)
        }
    }

    // MARK: - The recall round

    func testARoundDealsEveryShapeStartingFromWhereThePlayerIs() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.moveAnchor(by: 1)
        let anchored = model.anchoredShape

        model.startRecall()
        XCTAssertEqual(model.challenge.total, model.shapes.count)
        XCTAssertEqual(model.challenge.prompt?.context.root.fret, anchored?.root.fret,
                       "the round starts on the shape already in front of the player")
    }

    /// Showing the answer during the question is the one thing a recall round
    /// must not do.
    func testTheTargetIsHiddenWhileTheQuestionStands() {
        let (model, _) = makeModel()
        model.startRecall()
        XCTAssertTrue(model.challenge.isAcceptingAnswers)
        XCTAssertNil(model.dots.first { $0.id.hasPrefix("octave-target-") },
                     "the octave must not be on the board while it is being asked for")

        let shape = model.currentShape!
        model.answerCell(string: shape.target.string, fret: shape.target.fret)
        XCTAssertEqual(model.challenge.phase, .correct)
        XCTAssertNotNil(model.dots.first { $0.id.hasPrefix("octave-target-") },
                        "and it must appear once found")
    }

    func testACorrectAnswerAdvancesAndAWrongOneDoesNot() {
        let (model, _) = makeModel()
        model.startRecall()
        let first = model.currentShape!

        model.answerCell(string: first.root.string, fret: first.root.fret) // the root, not the octave
        XCTAssertEqual(model.challenge.phase, .incorrect)
        XCTAssertEqual(model.challenge.index, 0, "a wrong answer must not move on")
        XCTAssertEqual(model.challenge.correctCount, 0)

        model.challenge.retry()
        XCTAssertEqual(model.challenge.phase, .prompt)
        XCTAssertEqual(model.currentShape?.root.fret, first.root.fret, "retry asks the same question")

        model.answerCell(string: first.target.string, fret: first.target.fret)
        XCTAssertEqual(model.challenge.phase, .correct)
        XCTAssertEqual(model.challenge.correctCount, 1)

        model.challenge.next()
        XCTAssertEqual(model.challenge.index, 1)
    }

    /// A wrong answer plays what was actually picked — hearing that it is not
    /// an octave is the correction.
    func testAWrongAnswerSoundsTheNoteThatWasPicked() {
        let (model, heard) = makeModel()
        model.startRecall()
        let shape = model.currentShape!
        heard.positions.removeAll()

        model.answerCell(string: shape.root.string, fret: shape.root.fret)
        XCTAssertEqual(heard.positions, [FretPosition(string: shape.root.string, fret: shape.root.fret)])
    }

    func testARoundCompletesWithItsScore() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.startRecall()
        let total = model.challenge.total

        for _ in 0..<total {
            let shape = model.currentShape!
            model.answerCell(string: shape.target.string, fret: shape.target.fret)
            model.challenge.next()
        }
        XCTAssertEqual(model.challenge.phase, .complete)
        XCTAssertEqual(model.challenge.correctCount, total)
    }

    /// Mid-round a tap is an answer, so it must not also move the shape —
    /// otherwise answering would change the question.
    func testTappingDuringARoundDoesNotMoveTheAnchor() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.startRecall()
        let anchor = model.anchorKey

        model.selectAnchor(string: 5, fret: 5)
        XCTAssertEqual(model.anchorKey, anchor)
        model.moveAnchor(by: 1)
        XCTAssertEqual(model.anchorKey, anchor)
    }

    func testStoppingARoundReturnsToTheAnchoredShape() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        let anchored = model.anchoredShape
        model.startRecall()
        model.challenge.next()
        model.stopRecall()

        XCTAssertEqual(model.challenge.phase, .idle)
        XCTAssertEqual(model.currentShape?.root.fret, anchored?.root.fret)
        XCTAssertTrue(model.pulses.isEmpty)
    }

    // MARK: - Persistence

    func testTheRootAndAnchorArePersisted() {
        let storage = MemoryStorage()
        let model = OctavesModuleModel(store: PracticeStateStore(storage: storage))
        model.selectRoot(PitchClass(5))
        model.moveAnchor(by: 1)

        let restored = OctavesModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.rootPitchClass.value, 5)
        XCTAssertEqual(restored.anchorKey, model.anchorKey)
    }

    /// Workstream 006 states that guided playback state stays transient. A
    /// half-finished round is not something to resume days later.
    func testARoundInProgressIsNotPersisted() {
        let storage = MemoryStorage()
        let model = OctavesModuleModel(store: PracticeStateStore(storage: storage))
        model.startRecall()
        XCTAssertTrue(model.challenge.isRunning)

        let restored = OctavesModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertFalse(restored.challenge.isRunning)
        XCTAssertEqual(restored.challenge.phase, .idle)
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
