import XCTest
@testable import Fretwork

final class TuningTests: XCTestCase {
    func testAllTuningsHaveUniqueIDsAndSixStrings() {
        XCTAssertEqual(Tunings.all.count, 15)
        XCTAssertEqual(Set(Tunings.all.map(\.id)).count, 15)
        XCTAssertTrue(Tunings.all.allSatisfy { $0.openMIDINotes.count == 6 })
    }

    /// `Tunings.all` is hand-ordered for the picker, so nothing but this
    /// stops a new case being declared and never listed.
    func testEveryTuningIDAppearsInTheCatalogue() {
        XCTAssertEqual(Set(Tunings.all.map(\.id)), Set(TuningID.allCases))
    }

    func testStandardTuningRetainsLowToHighMIDIOrder() {
        XCTAssertEqual(Tunings.standard.openMIDINotes, [40, 45, 50, 55, 59, 64])
        XCTAssertEqual(Tunings.standard.stringNames, ["Low E", "A", "D", "G", "B", "High E"])
    }

    func testTuningDisplaysAreDerivedFromOpenStrings() {
        XCTAssertEqual(Tunings.standard.display, "E-A-D-G-B-E")
        XCTAssertEqual(Tunings.dadgad.display, "D-A-D-G-A-D")
    }

    func testDropDAddsLowOpenD() {
        XCTAssertFalse(GuitarTuning.positions(forMIDI: 38).contains(FretPosition(string: 0, fret: 0)))
        XCTAssertTrue(GuitarTuning.positions(forMIDI: 38, tuning: Tunings.dropD).contains(FretPosition(string: 0, fret: 0)))
    }

    func testMinimumFretDistanceAcrossSupportedTuningsIsDADGADsTwoFrets() {
        let minimum = Tunings.all.flatMap { tuning in
            (0...127).flatMap { midi -> [(TuningID, Int)] in
                let positions = GuitarTuning.positions(forMIDI: midi, tuning: tuning)
                return positions.indices.flatMap { left in
                    positions.dropFirst(left + 1).map { right in
                        (tuning.id, abs(positions[left].fret - right.fret))
                    }
                }
            }
        }.min { $0.1 < $1.1 }
        XCTAssertEqual(minimum?.0, .dadgad)
        XCTAssertEqual(minimum?.1, 2)
    }

    func testNonStandardTuningUsesReachableFallbackInsteadOfStandardChart() {
        let chord = ChordMatch(root: "D", quality: .major, confidence: 1)
        let standard = ChordShapeResolver.fingering(for: chord)
        let dropD = ChordShapeResolver.fingering(for: chord, tuning: Tunings.dropD)
        XCTAssertEqual(standard.count, 4)
        XCTAssertNotEqual(dropD.map { "\($0.string):\($0.fret)" }, standard.map { "\($0.string):\($0.fret)" })
    }
}
