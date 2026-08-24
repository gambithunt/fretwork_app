import XCTest
@testable import Fretwork

final class ScaleShapeTests: XCTestCase {
    func testPentatonicStepsHaveCorrectScaleMembershipAndMIDI() {
        for quality in [PentatonicQuality.minorPentatonic, .majorPentatonic] {
            let scale = Scales.scale(id: quality.rawValue)!
            for root in PitchClass.chromatic {
                let members = Set(scale.intervals.map { root.transposed(by: $0) })
                for position in 0..<5 {
                    for step in ScaleShapes.pentatonicPosition(root: root, quality: quality, position: position) {
                        XCTAssertTrue(members.contains(step.pitchClass))
                        XCTAssertEqual(step.midiNote, Tunings.standard.openMIDINotes[step.string] + step.fret)
                    }
                }
            }
        }
    }

    func testOneOctaveScaleStepsHaveCorrectMembershipAndMIDI() {
        for quality in [OneOctaveScaleQuality.major, .naturalMinor] {
            let scale = Scales.scale(id: quality.rawValue)!
            for root in PitchClass.chromatic {
                let members = Set(scale.intervals.map { root.transposed(by: $0) })
                for step in ScaleShapes.oneOctaveScale(root: root, quality: quality) {
                    XCTAssertTrue(members.contains(step.pitchClass))
                    XCTAssertEqual(step.midiNote, Tunings.standard.openMIDINotes[step.string] + step.fret)
                }
            }
        }
    }

    /// `oneOctaveScale` claims to be tuning-general because it derives every
    /// note from MIDI rather than from fixed offsets. This is what holds it to
    /// that claim; the pentatonic boxes make no such claim and take no tuning.
    func testOneOctaveScaleStaysInScaleUnderANonStandardTuning() {
        for quality in [OneOctaveScaleQuality.major, .naturalMinor] {
            let scale = Scales.scale(id: quality.rawValue)!
            for root in PitchClass.chromatic {
                let members = Set(scale.intervals.map { root.transposed(by: $0) })
                let steps = ScaleShapes.oneOctaveScale(root: root, quality: quality, tuning: Tunings.dropD)
                XCTAssertFalse(steps.isEmpty)
                for step in steps {
                    XCTAssertTrue(members.contains(step.pitchClass), "\(quality) \(root.value) string \(step.string)")
                    XCTAssertEqual(step.midiNote, Tunings.dropD.openMIDINotes[step.string] + step.fret)
                }
            }
        }
    }

    func testSecondAMinorBoxUsesLowToHighStringOrder() {
        let steps = ScaleShapes.pentatonicPosition(root: PitchClass(9), quality: .minorPentatonic, position: 1)
        let frets = Dictionary(grouping: steps, by: \.string).mapValues { $0.map(\.fret).sorted() }
        XCTAssertEqual(frets[0], [8, 10]); XCTAssertEqual(frets[1], [7, 10]); XCTAssertEqual(frets[2], [7, 10])
        XCTAssertEqual(frets[3], [7, 9]); XCTAssertEqual(frets[4], [8, 10]); XCTAssertEqual(frets[5], [8, 10])
    }

    func testGeneratedFingersAndPentatonicFretsStayInBounds() {
        for quality in [PentatonicQuality.minorPentatonic, .majorPentatonic] {
            for root in PitchClass.chromatic {
                for position in 0..<5 {
                    for step in ScaleShapes.pentatonicPosition(root: root, quality: quality, position: position) {
                        XCTAssertTrue((0...ScaleShapes.pentatonicFretCount).contains(step.fret))
                        XCTAssertEqual(step.finger == .open, step.fret == 0)
                        if step.fret > 0 { XCTAssertTrue((1...4).contains(step.finger.rawValue)) }
                    }
                }
            }
        }
        for quality in [OneOctaveScaleQuality.major, .naturalMinor] {
            for root in PitchClass.chromatic {
                for step in ScaleShapes.oneOctaveScale(root: root, quality: quality) {
                    XCTAssertEqual(step.finger == .open, step.fret == 0)
                    if step.fret > 0 { XCTAssertTrue((1...4).contains(step.finger.rawValue)) }
                }
            }
        }
    }

    func testUpDownSequenceDoesNotRepeatTopNote() {
        let steps = ScaleShapes.oneOctaveScale(root: PitchClass(0), quality: .major)
        let route = ScaleShapes.buildScaleSequence(steps, upDown: true)
        XCTAssertEqual(route.count, 2 * steps.count - 1)
        XCTAssertEqual(route[steps.count - 1].midiNote, route.map(\.midiNote).max())
        XCTAssertNotEqual(route[steps.count - 1].id, route[steps.count].id)
    }

    func testOctaveShapesMoveToHigherStringAndSoundAnOctave() {
        for root in PitchClass.chromatic {
            for shape in OctaveShapes.shapes(root: root, fretCount: 12) {
                XCTAssertEqual(shape.target.midiNote, shape.root.midiNote + 12)
                XCTAssertGreaterThan(shape.target.string, shape.root.string)
            }
        }
    }

    func testFirstPositionSearchesFromLowStrings() {
        let position = Positions.firstPosition(pitchClass: PitchClass(4), fretCount: 12)
        XCTAssertEqual(position?.string, 0)
        XCTAssertEqual(position?.fret, 0)
    }
}
