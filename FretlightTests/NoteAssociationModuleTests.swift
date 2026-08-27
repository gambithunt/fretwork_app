import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/NoteAssociation.svelte`, the
/// capstone.
///
/// The module's claim is that a note's *job* changes as the chord moves while
/// the note stays put. So the assertions are about roles: which layer a pitch
/// falls into, that the precedence between layers is stable, and that playing a
/// progression re-colours the board without moving a single dot.
@MainActor
final class NoteAssociationModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel() -> (NoteAssociationModuleModel, Heard) {
        let heard = Heard()
        let model = NoteAssociationModuleModel { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - Roles

    /// A chord tone is a chord tone even when it is also in the pentatonic:
    /// while this chord sounds, that is the stronger fact.
    func testChordTonesOutrankThePentatonic() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectMajor(true)
        model.selectDegree(0) // C major: C E G

        for pitchClass in [PitchClass(0), PitchClass(4), PitchClass(7)] {
            guard case .chordTone = model.role(of: pitchClass) else {
                return XCTFail("\(pitchClass.name()) should be a chord tone of C")
            }
        }
        // D is in the C major pentatonic but not in the C chord.
        XCTAssertEqual(model.role(of: PitchClass(2)), .pentatonic)
    }

    func testEveryScaleNoteHasARoleAndEveryOtherNoteDoesNot() {
        let (model, _) = makeModel()
        for major in [true, false] {
            model.selectMajor(major)
            for root in 0..<12 {
                model.selectKeyRoot(PitchClass(root))
                let scale = Set(model.scaleNotes.map(\.value))
                for value in 0..<12 {
                    let role = model.role(of: PitchClass(value))
                    if scale.contains(value) {
                        XCTAssertNotEqual(role, .outside,
                                          "\(PitchClass(value).name()) is in \(model.keyName) but has no role")
                    } else {
                        XCTAssertEqual(role, .outside,
                                       "\(PitchClass(value).name()) is not in \(model.keyName)")
                    }
                }
            }
        }
    }

    func testTheChordToneDegreeMatchesTheChord() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        for degree in 0...6 {
            model.selectDegree(degree)
            guard let chord = model.chord else { return XCTFail("no chord") }
            for (index, pitchClass) in chord.pitchClasses.enumerated() {
                guard case .chordTone(let label) = model.role(of: pitchClass) else {
                    return XCTFail("\(pitchClass.name()) should be a chord tone of \(chord.name)")
                }
                XCTAssertEqual(label, chord.degrees[index])
            }
        }
    }

    // MARK: - Layers

    func testTurningOffALayerHidesOnlyThatLayer() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectDegree(0)

        let all = model.dots.count
        model.setLayer(scale: false)
        let withoutScale = model.dots.count
        XCTAssertLessThan(withoutScale, all)
        XCTAssertTrue(model.dots.allSatisfy { model.role(of: pitchClass(of: $0, model)) != .scale })

        model.setLayer(pentatonic: false)
        XCTAssertTrue(model.dots.allSatisfy {
            if case .chordTone = model.role(of: pitchClass(of: $0, model)) { return true }
            return false
        }, "only chord tones should remain")

        model.setLayer(chordTones: false)
        XCTAssertTrue(model.dots.isEmpty, "with every layer off the board is empty")
    }

    private func pitchClass(of dot: FretboardDot, _ model: NoteAssociationModuleModel) -> PitchClass {
        PitchClass(model.tuning.openMIDINotes[dot.position.string] + dot.position.fret)
    }

    /// A note in both layers keeps its chord colour and gains a ring, so both
    /// facts are visible rather than one hiding the other.
    func testANoteInBothLayersShowsBoth() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectDegree(0)
        model.setLayer(chordTones: true, pentatonic: true, scale: true)

        // C is both a chord tone of C and in the C major pentatonic.
        let cDots = model.dots.filter { pitchClass(of: $0, model).value == 0 }
        XCTAssertFalse(cDots.isEmpty)
        XCTAssertTrue(cDots.allSatisfy { $0.ring != nil }, "a shared note should carry the pentatonic ring")
    }

    /// Turning a layer off is a view change and must not disturb the key.
    func testLayersDoNotChangeWhatIsInTheKey() {
        let (model, _) = makeModel()
        let notes = model.scaleNotes.map(\.value)
        model.setLayer(chordTones: false, pentatonic: false, scale: false)
        XCTAssertEqual(model.scaleNotes.map(\.value), notes)
    }

    // MARK: - The board does not move

    /// The whole idea: as the chord changes, the colours change and the dots do
    /// not. A dot that moved would be teaching the opposite lesson.
    func testChangingChordRecoloursWithoutMovingAnyDot() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectMajor(true)

        model.selectDegree(0)
        let firstPositions = model.dots.map { "\($0.position.string):\($0.position.fret)" }.sorted()
        let firstColours = model.dots.map { "\($0.id):\($0.color.description)" }.sorted()

        model.selectDegree(4)
        let secondPositions = model.dots.map { "\($0.position.string):\($0.position.fret)" }.sorted()
        let secondColours = model.dots.map { "\($0.id):\($0.color.description)" }.sorted()

        XCTAssertEqual(firstPositions, secondPositions, "the notes must stay where they are")
        XCTAssertNotEqual(firstColours, secondColours, "but their roles must change")
    }

    // MARK: - Progressions

    func testAProgressionResolvesToTheKeysChords() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectMajor(true)
        model.selectProgression(.pop1564)

        let chords = model.progressionChords
        XCTAssertEqual(chords.map(\.roman), ["I", "V", "vi", "IV"])
        for chord in chords {
            XCTAssertTrue(model.chords.contains { $0.roman == chord.roman },
                          "\(chord.roman) is not a chord of the key")
        }
    }

    /// A progression written only for major must not silently appear in minor.
    func testOnlyApplicableProgressionsAreOffered() {
        let (model, _) = makeModel()
        model.selectMajor(true)
        XCTAssertFalse(model.progressions.isEmpty)

        model.selectMajor(false)
        for progression in model.progressions {
            XCTAssertTrue(progression.applicableModes.contains(.minor),
                          "\(progression.name) is not written for minor")
        }
    }

    /// Switching to a mode the current progression is not written for must fall
    /// back rather than leave an empty bar.
    func testSwitchingModeFallsBackToAnApplicableProgression() {
        let (model, _) = makeModel()
        model.selectMajor(true)
        model.selectProgression(.pop1564)
        model.selectMajor(false)

        if !model.progressions.isEmpty {
            XCTAssertTrue(model.progressions.contains { $0.id == model.progressionID },
                          "the selected progression must be one that applies")
        }
    }

    func testPlayingAProgressionStartsAndStops() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectMajor(true)
        model.selectProgression(.pop1564)

        model.startProgression()
        XCTAssertNotEqual(model.progressionSnapshot.status, .idle)
        XCTAssertEqual(model.progressionSnapshot.total, model.progressionChords.count)

        model.stopEverything()
        XCTAssertEqual(model.progressionSnapshot.status, .idle)
        XCTAssertNil(model.playingDegree, "the focus returns to the chosen chord")
    }

    func testChangingTheKeyStopsPlayback() {
        let (model, _) = makeModel()
        model.selectMajor(true)
        for change in [
            { model.selectKeyRoot(PitchClass(5)) },
            { model.selectDegree(2) },
            { model.selectProgression(.iiVI) }
        ] {
            model.startProgression()
            XCTAssertNotEqual(model.progressionSnapshot.status, .idle)
            change()
            XCTAssertEqual(model.progressionSnapshot.status, .idle)
        }
    }

    /// Relabelling is a view change, so it must not interrupt playback — the
    /// same rule as Scales.
    func testRelabellingDoesNotStopPlayback() {
        let (model, _) = makeModel()
        model.selectMajor(true)
        model.startProgression()
        model.setLabelMode(.degrees)
        XCTAssertNotEqual(model.progressionSnapshot.status, .idle)
        model.setLayer(scale: false)
        XCTAssertNotEqual(model.progressionSnapshot.status, .idle, "a layer toggle is also a view change")
        model.stopEverything()
    }

    // MARK: - Persistence

    func testEverythingIsPersisted() {
        let storage = MemoryStorage()
        let model = NoteAssociationModuleModel(store: PracticeStateStore(storage: storage))
        model.selectKeyRoot(PitchClass(7))
        model.selectDegree(3)
        model.setLoop(true)
        model.setLabelMode(.degrees)
        model.setLayer(chordTones: true, pentatonic: false, scale: true)

        let restored = NoteAssociationModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.keyRoot.value, 7)
        XCTAssertEqual(restored.selectedDegree, 3)
        XCTAssertTrue(restored.loop)
        XCTAssertEqual(restored.labelMode, .degrees)
        XCTAssertFalse(restored.showsPentatonic)
        XCTAssertTrue(restored.showsChordTones)
    }

    func testUnknownSavedValuesFallBack() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"noteAssociation":{"rootPitchClass":4,"progressionID":"nope","labelMode":"runes","chordDegree":31}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.noteAssociation.progressionID, ProgressionID.pop1564.rawValue)
        XCTAssertEqual(decoded.modules.noteAssociation.labelMode, "notes")
        XCTAssertEqual(decoded.modules.noteAssociation.chordDegree, 6)
        XCTAssertEqual(decoded.modules.noteAssociation.rootPitchClass, 4)
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
