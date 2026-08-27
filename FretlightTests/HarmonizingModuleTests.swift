import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/Harmonizing.svelte`.
///
/// The module's claim is that a key's chords fall out of its scale rather than
/// being a list to memorise, so the tests check exactly that: the chord at a
/// degree must be the three stacked scale tones, and the famous quality pattern
/// must hold in every key.
@MainActor
final class HarmonizingModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel() -> (HarmonizingModuleModel, Heard) {
        let heard = Heard()
        let model = HarmonizingModuleModel { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - The chords come from the scale

    /// The point of the module: the chord at a degree is that scale tone plus
    /// the two above it in thirds — nothing else decides it.
    func testEachChordIsTheThreeStackedScaleTones() {
        let (model, _) = makeModel()
        for major in [true, false] {
            model.selectMajor(major)
            for root in 0..<12 {
                model.selectKeyRoot(PitchClass(root))
                for degree in 0...6 {
                    model.selectDegree(degree)
                    guard let chord = model.chord else { return XCTFail("no chord") }
                    XCTAssertEqual(
                        Set(model.stackedTones.map(\.value)),
                        Set(chord.pitchClasses.map(\.value)),
                        "\(PitchClass(root).name()) \(major ? "major" : "minor") degree \(degree)"
                    )
                }
            }
        }
    }

    /// The pattern every player learns: major keys go major, minor, minor,
    /// major, major, minor, diminished. It must hold in all twelve keys.
    func testTheMajorKeyQualityPatternHoldsEverywhere() {
        let (model, _) = makeModel()
        model.selectMajor(true)
        let expected = ["maj", "min", "min", "maj", "maj", "min", "dim"]
        for root in 0..<12 {
            model.selectKeyRoot(PitchClass(root))
            XCTAssertEqual(model.chords.map(\.quality), expected, "key of \(PitchClass(root).name())")
        }
    }

    func testTheMinorKeyQualityPatternHoldsEverywhere() {
        let (model, _) = makeModel()
        model.selectMajor(false)
        let expected = ["min", "dim", "maj", "min", "min", "maj", "maj"]
        for root in 0..<12 {
            model.selectKeyRoot(PitchClass(root))
            XCTAssertEqual(model.chords.map(\.quality), expected, "key of \(PitchClass(root).name())")
        }
    }

    func testAKeyHasSevenDegrees() {
        let (model, _) = makeModel()
        for major in [true, false] {
            model.selectMajor(major)
            XCTAssertEqual(model.chords.count, 7)
            XCTAssertEqual(Set(model.chords.map(\.roman)).count, 7, "each degree is named once")
        }
    }

    /// A relative major and minor are the same seven chords, started in a
    /// different place — which is the fact the module is quietly teaching.
    func testARelativeMinorHasTheSameChordsAsItsMajor() {
        let (model, _) = makeModel()
        model.selectMajor(true)
        model.selectKeyRoot(PitchClass(0))
        let major = Set(model.chords.map { "\($0.root.value):\($0.quality)" })

        model.selectMajor(false)
        model.selectKeyRoot(PitchClass(9))
        let minor = Set(model.chords.map { "\($0.root.value):\($0.quality)" })

        XCTAssertEqual(major, minor, "C major and A minor are the same seven chords")
    }

    // MARK: - The shape

    func testTheVoicingSoundsTheChordItNames() {
        let (model, _) = makeModel()
        for major in [true, false] {
            model.selectMajor(major)
            for root in 0..<12 {
                model.selectKeyRoot(PitchClass(root))
                for degree in 0...6 {
                    model.selectDegree(degree)
                    guard let chord = model.chord, let voicing = model.voicing else {
                        return XCTFail("no voicing for degree \(degree) of \(PitchClass(root).name())")
                    }
                    XCTAssertEqual(
                        Set(voicing.tones.map(\.position.pitchClass.value)),
                        Set(chord.pitchClasses.map(\.value)),
                        "\(chord.name) is voiced with the wrong notes"
                    )
                }
            }
        }
    }

    func testTheVoicingStaysOnTheModulesBoard() {
        let (model, _) = makeModel()
        for root in 0..<12 {
            model.selectKeyRoot(PitchClass(root))
            for degree in 0...6 {
                model.selectDegree(degree)
                for tone in model.voicing?.tones ?? [] {
                    XCTAssertGreaterThanOrEqual(tone.position.fret, 0)
                    XCTAssertLessThanOrEqual(tone.position.fret, LearningModule.harmonizing.highestFret)
                }
            }
        }
    }

    func testEveryChordShowsItsRoot() {
        let (model, _) = makeModel()
        for degree in 0...6 {
            model.selectDegree(degree)
            XCTAssertTrue(model.dots.contains { $0.label == "1" }, "degree \(degree) has no root marker")
        }
    }

    // MARK: - Selection

    func testSteppingThroughDegreesChangesTheChord() {
        let (model, _) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectMajor(true)
        var seen: [String] = []
        for degree in 0...6 {
            model.selectDegree(degree)
            seen.append(model.chord?.name ?? "")
        }
        XCTAssertEqual(Set(seen).count, 7, "each degree names a different chord")
    }

    func testAnOutOfRangeDegreeIsIgnored() {
        let (model, _) = makeModel()
        model.selectDegree(3)
        model.selectDegree(9)
        XCTAssertEqual(model.degree, 3, "an impossible degree must not be accepted")
        model.selectDegree(-1)
        XCTAssertEqual(model.degree, 3)
    }

    func testPlayingSoundsEveryNoteOfTheChord() {
        let (model, heard) = makeModel()
        model.selectKeyRoot(PitchClass(0))
        model.selectDegree(0)
        guard let voicing = model.voicing else { return XCTFail("no voicing") }
        model.strum()

        let settled = expectation(description: "strum")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(
            Set(heard.positions.map { "\($0.string):\($0.fret)" }),
            Set(voicing.tones.map { "\($0.position.string):\($0.position.fret)" })
        )
    }

    // MARK: - Persistence

    func testTheKeyAndDegreeArePersisted() {
        let storage = MemoryStorage()
        let model = HarmonizingModuleModel(store: PracticeStateStore(storage: storage))
        model.selectKeyRoot(PitchClass(7))
        model.selectMajor(false)
        model.selectDegree(4)

        let restored = HarmonizingModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.keyRoot.value, 7)
        XCTAssertFalse(restored.isMajor)
        XCTAssertEqual(restored.degree, 4)
    }

    func testAnOutOfRangeSavedDegreeIsClamped() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"harmonizing":{"keyRootPitchClass":2,"degree":42}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.harmonizing.degree, 6)
        XCTAssertEqual(decoded.modules.harmonizing.keyRootPitchClass, 2)
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
