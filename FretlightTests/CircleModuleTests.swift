import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/CircleOfFifths.svelte`.
///
/// The circle's claim is that its arrangement means something: a step
/// clockwise is a fifth, neighbours share all but one note, and the key
/// opposite is the furthest from home. Those are the assertions worth having —
/// a ring drawn in the wrong order still looks like a circle of fifths.
@MainActor
final class CircleModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel() -> (CircleModuleModel, Heard) {
        let heard = Heard()
        let model = CircleModuleModel { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - The ring is really fifths

    func testEachStepClockwiseIsAFifthUp() {
        let (model, _) = makeModel()
        let keys = model.keys
        XCTAssertEqual(keys.count, 12)
        for index in 0..<12 {
            let here = keys[index]
            let next = keys[(index + 1) % 12]
            XCTAssertEqual(next.value, here.transposed(by: 7).value,
                           "\(here.name()) → \(next.name()) is not a fifth")
        }
    }

    func testEveryKeyAppearsExactlyOnce() {
        let (model, _) = makeModel()
        XCTAssertEqual(Set(model.keys.map(\.value)).count, 12)
    }

    func testTheRingStartsAtC() {
        let (model, _) = makeModel()
        XCTAssertEqual(model.keys.first?.value, 0, "the circle is conventionally drawn with C at the top")
    }

    /// The fact that makes the circle worth drawing.
    func testNeighbouringKeysShareAllButOneNote() {
        let (model, _) = makeModel()
        for key in model.keys {
            model.select(key)
            XCTAssertEqual(model.sharedNoteCount(with: model.dominant), 6,
                           "\(key.name()) and \(model.dominant.name()) should differ by one note")
            XCTAssertEqual(model.sharedNoteCount(with: model.subdominant), 6,
                           "\(key.name()) and \(model.subdominant.name()) should differ by one note")
        }
    }

    /// And the other end of the same fact: opposite is furthest.
    func testTheKeyOppositeSharesTheFewestNotes() {
        let (model, _) = makeModel()
        for key in model.keys {
            model.select(key)
            let opposite = model.keys[(model.selectedIndex + 6) % 12]
            let shared = model.sharedNoteCount(with: opposite)
            for other in model.keys where other != key {
                XCTAssertGreaterThanOrEqual(model.sharedNoteCount(with: other), shared,
                                            "\(other.name()) is further from \(key.name()) than the opposite key")
            }
        }
    }

    // MARK: - Roles

    func testTheRolesAreTonicAndItsTwoNeighbours() {
        let (model, _) = makeModel()
        model.select(PitchClass(0))
        XCTAssertEqual(model.role(at: model.selectedIndex), .tonic)
        XCTAssertEqual(model.dominant.value, 7, "a fifth up from C is G")
        XCTAssertEqual(model.subdominant.value, 5, "a fifth down from C is F")

        let roles = (0..<12).map { model.role(at: $0) }
        XCTAssertEqual(roles.filter { $0 == .tonic }.count, 1)
        XCTAssertEqual(roles.filter { $0 == .dominant }.count, 1)
        XCTAssertEqual(roles.filter { $0 == .subdominant }.count, 1)
        XCTAssertEqual(roles.filter { $0 == .none }.count, 9, "the rest are context")
    }

    /// I–IV–V are neighbours on the ring — the same fact stated musically.
    func testTheThreeChordSongIsThreeAdjacentKeys() {
        let (model, _) = makeModel()
        model.select(PitchClass(0))
        let chords = Harmony.diatonicChords(root: PitchClass(0), major: true)
        XCTAssertEqual(chords[3].root.value, model.subdominant.value, "IV is the key a fifth down")
        XCTAssertEqual(chords[4].root.value, model.dominant.value, "V is the key a fifth up")
    }

    func testTheRelativeMinorIsThreeSemitonesDown() {
        let (model, _) = makeModel()
        for key in model.keys {
            model.select(key)
            XCTAssertEqual(model.relativeMinor.value, key.transposed(by: 9).value)
            // And it is the same seven notes.
            XCTAssertEqual(
                Set(Harmony.keyScalePitchClasses(root: key, major: true).map(\.value)),
                Set(Harmony.keyScalePitchClasses(root: model.relativeMinor, major: false).map(\.value)),
                "\(key.name()) major and \(model.relativeMinor.name()) minor are the same notes"
            )
        }
    }

    // MARK: - Geometry

    /// Twelve keys evenly spaced, C at the top and going clockwise.
    func testTheKeysAreEvenlySpacedAroundTheRing() {
        XCTAssertEqual(CircleModuleModel.angle(forIndex: 0), 0)
        XCTAssertEqual(CircleModuleModel.angle(forIndex: 3), 90)
        XCTAssertEqual(CircleModuleModel.angle(forIndex: 6), 180)
        XCTAssertEqual(CircleModuleModel.angle(forIndex: 11), 330)
    }

    // MARK: - The tonic triad

    func testTheTriadIsTheTonicChordOfTheSelectedKey() {
        let (model, _) = makeModel()
        for key in model.keys {
            model.select(key)
            let expected = Set([0, 4, 7].map { key.transposed(by: $0).value })
            let actual = Set(model.triadPositions.map(\.pitchClass.value))
            XCTAssertEqual(actual, expected, "\(key.name()) major triad")
        }
    }

    func testTheTriadStaysOnTheSmallBoard() {
        let (model, _) = makeModel()
        for key in model.keys {
            model.select(key)
            for entry in model.triadPositions {
                XCTAssertGreaterThanOrEqual(entry.position.fret, 0)
                XCTAssertLessThanOrEqual(entry.position.fret, 12)
            }
        }
    }

    func testPlayingSoundsTheTriad() {
        let (model, heard) = makeModel()
        model.select(PitchClass(0))
        let positions = model.triadPositions.map(\.position)
        model.strum()

        let settled = expectation(description: "strum")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(Set(heard.positions.map { "\($0.string):\($0.fret)" }),
                       Set(positions.map { "\($0.string):\($0.fret)" }))
    }

    // MARK: - Stepping

    func testSteppingMovesAroundTheRingAndWraps() {
        let (model, _) = makeModel()
        model.select(PitchClass(0))
        model.step(by: 1)
        XCTAssertEqual(model.selected.value, 7, "clockwise from C is G")
        model.step(by: -1)
        XCTAssertEqual(model.selected.value, 0)
        model.step(by: -1)
        XCTAssertEqual(model.selected.value, 5, "anticlockwise from C is F")

        model.select(PitchClass(0))
        for _ in 0..<12 { model.step(by: 1) }
        XCTAssertEqual(model.selected.value, 0, "a full lap returns home")
    }

    // MARK: - Persistence

    func testTheSelectedKeyIsPersisted() {
        let storage = MemoryStorage()
        let model = CircleModuleModel(store: PracticeStateStore(storage: storage))
        model.select(PitchClass(3))

        let restored = CircleModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.selected.value, 3)
    }

    func testAnOutOfRangeSavedKeyWraps() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"circle":{"selectedPitchClass":14}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.circle.selectedPitchClass, 2)
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
