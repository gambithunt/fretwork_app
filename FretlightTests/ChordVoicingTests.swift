import XCTest
@testable import Fretwork

final class ChordVoicingTests: XCTestCase {
    func testEveryFormulaSoundsExactlyItsTonesForEveryRoot() {
        for formula in ChordFormulas.all {
            for rootValue in 0..<12 {
                let root = PitchClass(rootValue)
                let expected = Set(formula.intervals.map { root.transposed(by: $0) })
                let voicings = ChordVoicings.voicings(root: root, formulaID: formula.id)
                XCTAssertFalse(voicings.isEmpty, "\(formula.id), root \(rootValue)")
                for voicing in voicings {
                    let sounded = Set(voicing.frets.enumerated().compactMap { string, fret in
                        fret.map { PitchClass(Tunings.standard.openMIDINotes[string] + $0) }
                    })
                    XCTAssertEqual(sounded, expected, "\(formula.id), root \(rootValue), shape \(voicing.id)")
                    XCTAssertTrue(sounded.contains(root), "\(formula.id), root \(rootValue), shape \(voicing.id)")
                }
            }
        }
    }

    func testCShapeWasReversedIntoLowToHighStringOrder() {
        let cShape = ChordVoicings.voicings(root: PitchClass(0), formulaID: "maj").first { $0.id == "c" }
        XCTAssertEqual(cShape?.frets, [nil, 3, 2, 0, 1, 0])
        XCTAssertNil(cShape?.frets[0])
        XCTAssertEqual(cShape?.frets[5], 0)
    }

    func testEveryVoicingFitsItsBoardForEveryRoot() {
        for formula in ChordFormulas.all {
            for root in PitchClass.chromatic {
                for voicing in ChordVoicings.voicings(root: root, formulaID: formula.id) {
                    XCTAssertTrue(voicing.frets.compactMap { $0 }.allSatisfy { (0...ChordVoicings.fretCount).contains($0) })
                }
            }
        }
    }

    func testPowerShapesContainOnlyRootAndFifth() {
        for root in PitchClass.chromatic {
            let expected: Set<PitchClass> = [root, root.transposed(by: 7)]
            for voicing in ChordVoicings.voicings(root: root, formulaID: "power") {
                let sounded = Set(voicing.frets.enumerated().compactMap { string, fret in
                    fret.map { PitchClass(Tunings.standard.openMIDINotes[string] + $0) }
                })
                XCTAssertEqual(sounded, expected)
            }
        }
    }

    func testTriadPathsUseMacLowToHighStringIndices() {
        XCTAssertEqual(TriadPaths.stringIndices(for: .ead), [0, 1, 2])
        let path = TriadPaths.path(root: PitchClass(0), triad: Triads.major, stringSet: .ead)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.allSatisfy { $0.voicing.tones.map { $0.position.string } == [0, 1, 2] })
    }
}
