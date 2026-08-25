import XCTest
@testable import Fretwork

final class HarmonyTests: XCTestCase {
    func testDiatonicHarmonyAcrossKeysAndModes() {
        for root in PitchClass.chromatic {
            for major in [true, false] {
                let scale = Set(Harmony.keyScalePitchClasses(root: root, major: major))
                let chords = Harmony.diatonicChords(root: root, major: major)
                XCTAssertEqual(chords.count, 7)
                XCTAssertTrue(chords.allSatisfy { $0.pitchClasses.allSatisfy(scale.contains) })
            }
        }
        XCTAssertEqual(Harmony.diatonicChords(root: PitchClass(0), major: true).map(\.quality), ["maj", "min", "min", "maj", "maj", "min", "dim"])
        XCTAssertEqual(Harmony.diatonicChords(root: PitchClass(0), major: true).map(\.name), ["C", "Dm", "Em", "F", "G", "Am", "B°"])
        XCTAssertEqual(Harmony.diatonicChords(root: PitchClass(9), major: false).map(\.name), ["Am", "B°", "C", "Dm", "Em", "F", "G"])
    }

    func testProgressionsAndKeyHelpers() {
        XCTAssertEqual(Progressions.resolve(root: PitchClass(0), major: true, progressionID: .pop1564).map(\.name), ["C", "G", "Am", "F"])
        XCTAssertEqual(Progressions.resolve(root: PitchClass(0), major: true, progressionID: .iiVI).map(\.name), ["Dm", "G", "C"])
        XCTAssertTrue(Progressions.resolve(root: PitchClass(0), major: false, progressionID: .iiVI).isEmpty)
        XCTAssertTrue(Set(Harmony.keyPentatonicPitchClasses(root: PitchClass(0), major: true)).isSubset(of: Set(Harmony.keyScalePitchClasses(root: PitchClass(0), major: true))))
    }

    func testCircleAndCompactVoicings() {
        XCTAssertEqual(Set(Harmony.circleOfFifths).count, 12)
        for index in Harmony.circleOfFifths.indices { XCTAssertEqual(Harmony.circleOfFifths[(index + 1) % 12], Harmony.circleOfFifths[index].transposed(by: 7)) }
        for root in PitchClass.chromatic {
            for triad in Triads.all {
                let first = Positions.compactVoicing(root: root, intervals: triad.intervals, fretCount: 12)
                XCTAssertEqual(first, Positions.compactVoicing(root: root, intervals: triad.intervals, fretCount: 12))
                XCTAssertEqual(Set(first.map(\.string)).count, first.count)
                XCTAssertEqual(Set(first.map(\.pitchClass)), Set(triad.intervals.map { root.transposed(by: $0) }))
            }
        }
    }

    func testDiatonicTriadPathStaysOnItsStringSetAndClimbsTheNeck() {
        let key = PitchClass(0)
        let steps = TriadPaths.diatonicPath(keyRoot: key, major: true, stringSet: .ead)
        XCTAssertFalse(steps.isEmpty)

        let diatonic = Set(Harmony.diatonicChords(root: key, major: true).map(\.root))
        for step in steps {
            XCTAssertEqual(step.voicing.tones.map(\.position.string), [0, 1, 2])
            XCTAssertTrue(diatonic.contains(step.chord.root))
        }
        XCTAssertEqual(steps.map(\.voicing.minFret), steps.map(\.voicing.minFret).sorted())
    }
}
