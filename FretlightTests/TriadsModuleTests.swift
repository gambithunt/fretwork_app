import XCTest
@testable import Fretwork

/// Ported from `../fretwork/src/lib/modules/Triads.svelte`, the largest of the
/// reference modules.
///
/// The assertions that matter are musical: a triad must actually contain its
/// three degrees, an inversion must be the *same* notes rearranged rather than a
/// different chord, and a path must never leave its string set — that constraint
/// is the whole exercise, so a path that wandered would be teaching nothing.
@MainActor
final class TriadsModuleTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        var positions: [FretPosition] = []
    }

    private func makeModel() -> (TriadsModuleModel, Heard) {
        let heard = Heard()
        let model = TriadsModuleModel { heard.positions.append($0) }
        return (model, heard)
    }

    // MARK: - Shapes

    /// Every voicing must sound the triad it claims: the right pitch classes,
    /// no more and no fewer.
    func testEveryVoicingContainsExactlyTheTriadsNotes() {
        let (model, _) = makeModel()
        for triad in Triads.all {
            model.selectTriad(triad)
            for root in 0..<12 {
                model.selectRoot(PitchClass(root))
                let expected = Set(triad.intervals.map { PitchClass(root + $0).value })
                for voicing in model.voicings {
                    let actual = Set(voicing.tones.map(\.position.pitchClass.value))
                    XCTAssertEqual(actual, expected,
                                   "\(PitchClass(root).name())\(triad.short) voicing \(voicing.id)")
                }
            }
        }
    }

    func testEveryVoicingCarriesEachDegreeExactlyOnce() {
        let (model, _) = makeModel()
        for triad in Triads.all {
            model.selectTriad(triad)
            for voicing in model.voicings {
                XCTAssertEqual(Set(voicing.tones.map(\.degree)).count, triad.degrees.count)
                XCTAssertEqual(voicing.tones.count, triad.intervals.count)
            }
        }
    }

    func testEveryVoicingStaysOnTheModulesBoard() {
        let (model, _) = makeModel()
        for triad in Triads.all {
            model.selectTriad(triad)
            for voicing in model.voicings {
                for tone in voicing.tones {
                    XCTAssertGreaterThanOrEqual(tone.position.fret, 0)
                    XCTAssertLessThanOrEqual(tone.position.fret, LearningModule.triads.highestFret)
                }
            }
        }
    }

    /// A compact voicing has to be reachable — the point of "compact" is that
    /// one hand can hold it.
    func testEveryVoicingIsWithinAHandsSpan() {
        let (model, _) = makeModel()
        for triad in Triads.all {
            model.selectTriad(triad)
            for voicing in model.voicings {
                let frets = voicing.tones.map(\.position.fret).filter { $0 > 0 }
                guard let low = frets.min(), let high = frets.max() else { continue }
                XCTAssertLessThanOrEqual(high - low, 5, "voicing \(voicing.id) needs a \(high - low)-fret stretch")
            }
        }
    }

    // MARK: - Inversions

    /// An inversion is the same three notes with a different one lowest. Not a
    /// different chord — which is exactly what a player gets wrong.
    func testAnInversionIsTheSameNotesWithADifferentBass() {
        let (model, _) = makeModel()
        model.selectTriad(Triads.major)
        model.selectRoot(PitchClass(0))

        var bassesByInversion: [String: Set<Int>] = [:]
        for voicing in model.voicings {
            let notes = Set(voicing.tones.map(\.position.pitchClass.value))
            XCTAssertEqual(notes, [0, 4, 7], "every inversion of C is still C E G")
            let bass = voicing.tones.min { $0.position.midiNote < $1.position.midiNote }
            if let bass {
                bassesByInversion[voicing.inversion, default: []].insert(bass.position.pitchClass.value)
            }
        }
        XCTAssertEqual(bassesByInversion["Root position"], [0], "root position has the root lowest")
        if let first = bassesByInversion["1st inversion"] {
            XCTAssertEqual(first, [4], "1st inversion has the third lowest")
        }
        if let second = bassesByInversion["2nd inversion"] {
            XCTAssertEqual(second, [7], "2nd inversion has the fifth lowest")
        }
    }

    func testSelectingAnInversionShowsThatInversion() {
        let (model, _) = makeModel()
        model.selectTriad(Triads.major)
        model.selectView(.inversions)
        for inversion in model.availableInversions {
            model.selectInversion(inversion)
            XCTAssertEqual(model.selectedInversion, inversion)
        }
    }

    func testEnteringTheInversionsViewStartsFromRootPosition() {
        let (model, _) = makeModel()
        model.selectTriad(Triads.major)
        model.movePosition(by: 3)
        model.selectView(.inversions)
        XCTAssertEqual(model.selectedInversion, "Root position")
    }

    // MARK: - Degree colouring

    /// The module colours by role rather than pitch, and the third is the note
    /// that decides major from minor — so it must never be coloured as anything
    /// else.
    func testDegreesMapToTheirRoles() {
        XCTAssertEqual(TriadsModuleModel.role(forDegree: "1"), .root)
        XCTAssertEqual(TriadsModuleModel.role(forDegree: "3"), .third)
        XCTAssertEqual(TriadsModuleModel.role(forDegree: "b3"), .third)
        XCTAssertEqual(TriadsModuleModel.role(forDegree: "5"), .fifth)
        XCTAssertEqual(TriadsModuleModel.role(forDegree: "b5"), .fifth)
        XCTAssertEqual(TriadsModuleModel.role(forDegree: "#5"), .fifth)
    }

    func testTheRootDotIsRingedSoTheShapeCanBeLocated() {
        let (model, _) = makeModel()
        model.selectTriad(Triads.major)
        let ringed = model.dots.filter { $0.ring != nil }
        XCTAssertEqual(ringed.count, 1, "exactly one root marker")
        XCTAssertEqual(ringed.first?.label, "1")
    }

    // MARK: - Double stops

    func testADoubleStopHasTwoNotes() {
        let (model, _) = makeModel()
        for pair in DoubleStops.all {
            model.selectDoubleStop(pair)
            XCTAssertEqual(model.view, .doubleStops)
            for voicing in model.voicings {
                XCTAssertEqual(voicing.tones.count, 2, "\(pair.label) voicing \(voicing.id)")
            }
        }
    }

    func testChoosingATriadLeavesTheDoubleStopView() {
        let (model, _) = makeModel()
        model.selectDoubleStop(DoubleStops.all[0])
        XCTAssertEqual(model.view, .doubleStops)
        model.selectTriad(Triads.minor)
        XCTAssertEqual(model.view, .shapes)
    }

    // MARK: - Paths

    /// The constraint that *is* the exercise.
    func testAPathNeverLeavesItsStringSet() {
        let (model, _) = makeModel()
        model.setPathMode(true)
        for stringSet in TriadPaths.stringSets {
            model.selectPathStringSet(stringSet)
            let allowed = Set(TriadPaths.stringIndices(for: stringSet))
            XCTAssertFalse(model.pathSteps.isEmpty, "\(stringSet.rawValue) has no path")
            for step in model.pathSteps {
                for tone in step.voicing.tones {
                    XCTAssertTrue(allowed.contains(tone.position.string),
                                  "\(stringSet.rawValue) wandered onto string \(tone.position.string)")
                }
            }
        }
    }

    /// A diatonic path contains the chords of the key and nothing else.
    ///
    /// Note what is *not* asserted: that the romans appear in scale order. The
    /// path is deliberately sorted up the neck rather than grouped by degree —
    /// `TriadPaths.diatonicPath` says so — because the exercise is to walk the
    /// harmony along one string set, so the degrees interleave by position.
    func testAMajorPathUsesOnlyTheDiatonicChordsOfTheKey() {
        let (model, _) = makeModel()
        model.setPathMode(true)
        model.selectRoot(PitchClass(0))
        model.setPathMajor(true)

        let expected = Set(Harmony.diatonicChords(root: PitchClass(0), major: true).map(\.roman))
        let seen = Set(model.pathSteps.map(\.chord.roman))
        XCTAssertEqual(seen, expected, "the path strayed outside the key")

        for step in model.pathSteps {
            let notes = Set(step.voicing.tones.map(\.position.pitchClass.value))
            XCTAssertEqual(notes, Set(step.chord.pitchClasses.map(\.value)),
                           "\(step.chord.roman) is voiced with the wrong notes")
        }
    }

    /// And it walks *up* the neck, which is the ordering the exercise depends
    /// on — a path that jumped around would not be a path.
    func testAPathIsOrderedUpTheNeck() {
        let (model, _) = makeModel()
        model.setPathMode(true)
        for stringSet in TriadPaths.stringSets {
            model.selectPathStringSet(stringSet)
            let frets = model.pathSteps.map(\.voicing.minFret)
            XCTAssertEqual(frets, frets.sorted(), "\(stringSet.rawValue) is not ordered up the neck")
        }
    }

    func testMinorAndMajorPathsDiffer() {
        let (model, _) = makeModel()
        model.setPathMode(true)
        model.selectRoot(PitchClass(9))
        model.setPathMajor(true)
        let major = model.pathSteps.map(\.chord.roman)
        model.setPathMajor(false)
        let minor = model.pathSteps.map(\.chord.roman)
        XCTAssertNotEqual(major, minor)
    }

    // MARK: - Progression playback

    func testAProgressionWalksTheStepsAndStops() {
        let (model, _) = makeModel()
        model.setPathMode(true)
        model.selectPathStringSet(.dgb)
        XCTAssertFalse(model.pathSteps.isEmpty)

        model.startProgression(loop: false)
        XCTAssertNotEqual(model.progressionSnapshot.status, .idle, "a started progression must leave idle")
        XCTAssertEqual(model.progressionSnapshot.total, model.pathSteps.count)

        model.stopProgression()
        XCTAssertEqual(model.progressionSnapshot.status, .idle)
    }

    /// A progression left running after the key changed would be playing the
    /// previous key's chords over the new key's shapes.
    func testChangingAnythingStopsTheProgression() {
        let (model, _) = makeModel()
        model.setPathMode(true)
        for change in [
            { model.selectRoot(PitchClass(5)) },
            { model.setPathMajor(false) },
            { model.selectPathStringSet(.gbe) }
        ] {
            model.startProgression(loop: true)
            XCTAssertNotEqual(model.progressionSnapshot.status, .idle)
            change()
            XCTAssertEqual(model.progressionSnapshot.status, .idle, "a selection change must stop playback")
        }
    }

    func testPlayingAVoicingSoundsEveryToneInIt() {
        let (model, heard) = makeModel()
        model.selectTriad(Triads.major)
        guard let voicing = model.activeVoicing else { return XCTFail("no voicing") }
        model.playVoicing()

        let settled = expectation(description: "strum")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(Set(heard.positions.map { "\($0.string):\($0.fret)" }),
                       Set(voicing.tones.map { "\($0.position.string):\($0.position.fret)" }))
    }

    // MARK: - Persistence

    func testShapeAndPathSettingsArePersistedSeparately() {
        let storage = MemoryStorage()
        let model = TriadsModuleModel(store: PracticeStateStore(storage: storage))
        model.selectTriad(Triads.minor)
        model.selectRoot(PitchClass(7))
        model.setPathMode(true)
        model.selectPathStringSet(.gbe)
        model.selectRoot(PitchClass(2))   // the key, not the shape root
        model.setPathMajor(false)

        let restored = TriadsModuleModel(store: PracticeStateStore(storage: storage))
        XCTAssertEqual(restored.triad.short, "min", "the shape triad survived")
        XCTAssertEqual(restored.rootPitchClass.value, 7, "and its root, untouched by the path key")
        XCTAssertEqual(restored.pathKeyRoot.value, 2)
        XCTAssertEqual(restored.pathStringSet, .gbe)
        XCTAssertFalse(restored.pathIsMajor)
        XCTAssertTrue(restored.isPathMode)
    }

    func testAnUnknownSavedTriadFallsBack() throws {
        let json = """
        {"version":1,"settings":{},"modules":{"triads":{"rootPitchClass":4,"triadShort":"wat","view":"nonsense"}}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modules.triads.triadShort, "maj")
        XCTAssertEqual(decoded.modules.triads.view, "shapes")
        XCTAssertEqual(decoded.modules.triads.rootPitchClass, 4, "and must not take the rest with it")
    }
}

private final class MemoryStorage: PracticeStorage {
    private var data: Data?
    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
