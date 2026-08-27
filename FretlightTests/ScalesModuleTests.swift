import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/Scales.svelte`, plus the guided
/// presentation shared with Pentatonic.
@MainActor
final class ScalesModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel(tuning: Tuning = Tunings.standard) -> (ScalesModuleModel, Heard) {
        let heard = Heard()
        let model = ScalesModuleModel(tuning: tuning) { heard.positions.append($0) }
        return (model, heard)
    }

    /// Derived independently of the shape generator, so this is a cross-check
    /// rather than a restatement.
    private func expected(root: Int, quality: OneOctaveScaleQuality) -> [Int] {
        let intervals = quality == .major ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        return intervals.map { PitchClass(root + $0).value }
    }

    // MARK: - The shape is the scale

    func testTheShapeIsAnOctaveOfTheScaleEndingOnTheRoot() {
        let (model, _) = makeModel()
        for quality in [OneOctaveScaleQuality.major, .naturalMinor] {
            model.selectQuality(quality)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                let steps = model.steps
                XCTAssertEqual(steps.count, 8, "\(PitchClass(root).name()) \(quality.rawValue)")
                XCTAssertEqual(steps.first?.pitchClass.value, root, "must start on the root")
                XCTAssertEqual(steps.last?.pitchClass.value, root, "must end on the root")
                XCTAssertEqual((steps.last?.midiNote ?? 0) - (steps.first?.midiNote ?? 0), 12,
                               "must span exactly one octave")
            }
        }
    }

    func testEveryNoteBelongsToTheScale() {
        let (model, _) = makeModel()
        for quality in [OneOctaveScaleQuality.major, .naturalMinor] {
            model.selectQuality(quality)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                let allowed = Set(expected(root: root, quality: quality))
                for step in model.steps {
                    XCTAssertTrue(allowed.contains(step.pitchClass.value),
                                  "\(PitchClass(root).name()) \(quality.rawValue) has \(step.pitchClass.name())")
                }
            }
        }
    }

    func testTheNotesAscendInPitch() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            let midis = model.steps.map(\.midiNote)
            XCTAssertEqual(midis, midis.sorted(), "a one-octave shape must ascend")
        }
    }

    /// Natural minor is the major scale with its 3rd, 6th and 7th flattened —
    /// which is exactly what the two shapes should differ by.
    func testMinorFlattensTheThirdSixthAndSeventh() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectQuality(.major)
        let major = model.steps.map(\.pitchClass.value)
        model.selectQuality(.naturalMinor)
        let minor = model.steps.map(\.pitchClass.value)

        XCTAssertEqual(major, [0, 2, 4, 5, 7, 9, 11, 0])
        XCTAssertEqual(minor, [0, 2, 3, 5, 7, 8, 10, 0])
    }

    /// Unlike Pentatonic and Chords, this generator derives from MIDI, so it
    /// transposes honestly rather than detuning.
    func testTheShapeFollowsANonStandardTuning() {
        let (model, _) = makeModel(tuning: Tunings.dropD)
        for root in 0..<12 {
            model.selectRoot(PitchClass(root))
            for step in model.steps {
                XCTAssertEqual(Tunings.dropD.openMIDINotes[step.string] + step.fret, step.midiNote,
                               "the note's pitch must come from the tuning in use")
            }
            XCTAssertEqual(model.steps.first?.pitchClass.value, root)
        }
    }

    func testEveryNoteStaysOnTheBoard() {
        let (model, _) = makeModel()
        for quality in [OneOctaveScaleQuality.major, .naturalMinor] {
            model.selectQuality(quality)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                for step in model.steps {
                    XCTAssertGreaterThanOrEqual(step.fret, 0)
                    XCTAssertLessThanOrEqual(step.fret, LearningModule.scales.highestFret)
                }
            }
        }
    }

    // MARK: - Direction

    func testAscendingPlaysEachNoteOnce() {
        let (model, _) = makeModel()
        model.selectDirection(.ascending)
        XCTAssertEqual(model.sequence.count, model.steps.count)
        XCTAssertEqual(model.sequence.map(\.midiNote), model.steps.map(\.midiNote))
    }

    /// Up and down comes back without repeating the top note — playing the
    /// octave twice in a row is the thing that makes a practice run sound like
    /// a stumble.
    func testUpDownComesBackWithoutRepeatingTheTopNote() {
        let (model, _) = makeModel()
        model.selectDirection(.upDown)
        let run = model.sequence
        XCTAssertEqual(run.count, model.steps.count * 2 - 1)
        XCTAssertNotEqual(run[model.steps.count - 1].midiNote, run[model.steps.count].midiNote,
                          "the top note must not sound twice")
        XCTAssertEqual(run.first?.midiNote, run.last?.midiNote, "and it must finish where it started")
    }

    // MARK: - Labels

    func testLabelModeSwitchesBetweenNotesAndDegrees() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectQuality(.major)

        model.selectLabelMode(.notes)
        XCTAssertEqual(model.dots.first?.label, "C")
        model.selectLabelMode(.degrees)
        XCTAssertEqual(model.dots.first?.label, "1")
    }

    /// Relabelling is a change of view, not of what is being practised, so it
    /// must not interrupt a run.
    func testRelabellingDoesNotStopARun() {
        let (model, _) = makeModel()
        model.startGuided()
        XCTAssertNotEqual(model.guidedSnapshot.status, .idle)
        model.selectLabelMode(.degrees)
        XCTAssertNotEqual(model.guidedSnapshot.status, .idle, "changing labels must not stop practice")
        model.stopGuided()
    }

    func testChangingTheScaleStopsARun() {
        let (model, _) = makeModel()
        for change in [
            { model.selectRoot(PitchClass(3)) },
            { model.selectQuality(.naturalMinor) },
            { model.selectDirection(.upDown) },
            { model.retune(to: Tunings.dropD) }
        ] {
            model.startGuided()
            XCTAssertNotEqual(model.guidedSnapshot.status, .idle)
            change()
            XCTAssertEqual(model.guidedSnapshot.status, .idle, "a change of what is practised must stop the run")
        }
    }

    // MARK: - Guided presentation

    /// The count-in exists so the shape can be read before the first beat, so
    /// nothing should be dimmed yet.
    func testTheWholeShapeStaysLegibleDuringTheCountIn() {
        let (model, _) = makeModel()
        model.startGuided()
        XCTAssertEqual(model.guidedSnapshot.status, .countIn)
        XCTAssertTrue(model.dots.allSatisfy { $0.alpha == 1 }, "nothing should dim before the run starts")
        model.stopGuided()
    }

    /// Emphasis is the instruction: the note to play now carries its fretting
    /// finger, the next is visible but recessed, the rest are context.
    func testWhilePlayingTheCurrentNoteShowsItsFinger() {
        let steps = ScaleShapes.oneOctaveScale(root: PitchClass(0), quality: .major)
        let dots = steps.map {
            FretboardDot(id: $0.id, position: FretPosition(string: $0.string, fret: $0.fret),
                         label: $0.pitchClass.name(), color: .white)
        }
        var snapshot = GuidedSession<GuidedScaleStep>.Snapshot()
        snapshot.status = .playing
        snapshot.currentIndex = 2

        let decorated = GuidedPresentation.decorate(dots, steps: steps, snapshot: snapshot)
        let current = decorated.first { $0.id == steps[2].id }
        XCTAssertEqual(current?.label, "\(steps[2].finger.rawValue)")
        XCTAssertEqual(current?.alpha, 1)
        XCTAssertNotNil(current?.ring)

        let next = decorated.first { $0.id == steps[3].id }
        XCTAssertEqual(next?.alpha, 0.72)
        XCTAssertLessThan(next?.radius ?? 99, FretboardDot.defaultRadius)

        let other = decorated.first { $0.id == steps[6].id }
        XCTAssertEqual(other?.alpha, 0.28)
    }

    /// The decorator must be given the *run*, not the shape: an up-and-down run
    /// is longer, so indexing the shape would emphasise the wrong note on the
    /// way back down, or none at all.
    func testTheEmphasisFollowsTheRunOnTheWayBackDown() {
        let (model, _) = makeModel()
        model.selectRoot(PitchClass(0))
        model.selectDirection(.upDown)
        let run = model.sequence
        let descendingIndex = model.steps.count + 1
        XCTAssertLessThan(descendingIndex, run.count)

        let dots = model.steps.map {
            FretboardDot(id: $0.id, position: FretPosition(string: $0.string, fret: $0.fret),
                         label: "", color: .white)
        }
        var snapshot = GuidedSession<GuidedScaleStep>.Snapshot()
        snapshot.status = .playing
        snapshot.currentIndex = descendingIndex

        let decorated = GuidedPresentation.decorate(dots, steps: run, snapshot: snapshot)
        XCTAssertEqual(decorated.filter { $0.alpha == 1 }.count, 1,
                       "exactly one note is emphasised on the way back down")
        XCTAssertEqual(decorated.first { $0.alpha == 1 }?.id, run[descendingIndex].id)
    }

    // MARK: - Persistence

    func testTheSelectionIsPersistedAndRestored() {
        let storage = MemoryStorage()
        let model = ScalesModuleModel(store: PracticeStateStore(storage: storage))
        model.selectRoot(PitchClass(8))
        model.selectQuality(.naturalMinor)
        model.selectLabelMode(.degrees)
        model.selectDirection(.upDown)

        let restored = ScalesModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.rootPitchClass.value, 8)
        XCTAssertEqual(restored.quality, .naturalMinor)
        XCTAssertEqual(restored.labelMode, .degrees)
        XCTAssertEqual(restored.direction, .upDown)
    }

    func testARunInProgressIsNotPersisted() {
        let storage = MemoryStorage()
        let model = ScalesModuleModel(store: PracticeStateStore(storage: storage))
        model.startGuided()

        let restored = ScalesModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.guidedSnapshot.status, .idle)
        XCTAssertNil(restored.currentStep)
    }

    func testUnknownSavedValuesFallBack() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"scales":{"rootPitchClass":5,"quality":"lydian","labelMode":"emoji","direction":"sideways"}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.scales.quality, "major")
        XCTAssertEqual(decoded.modules.scales.labelMode, "notes")
        XCTAssertEqual(decoded.modules.scales.direction, "ascending")
        XCTAssertEqual(decoded.modules.scales.rootPitchClass, 5, "and must not take the rest with it")
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
