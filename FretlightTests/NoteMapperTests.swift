import XCTest
@testable import Fretwork

final class NoteMapperTests: XCTestCase {
    func testA2ResolvesToPitch() {
        let note = NoteMapper.map(frequency: 110)!
        XCTAssertEqual(note.name, "A"); XCTAssertEqual(note.octave, 2); XCTAssertEqual(note.cents, 0, accuracy: 0.01)
        XCTAssertEqual(note.midiNote, 45)
    }
    func testInvalidFrequencyHasNoMapping() { XCTAssertNil(NoteMapper.map(frequency: 0)) }

    func testA2CanBePlayedOpenOrAtTheFifthFret() {
        let positions = GuitarTuning.positions(forMIDI: 45)
        XCTAssertTrue(positions.contains(FretPosition(string: 1, fret: 0)))
        XCTAssertTrue(positions.contains(FretPosition(string: 0, fret: 5)))
        XCTAssertEqual(positions.count, 2)
    }

    func testPositionsStayWithinTheFretCount() {
        XCTAssertTrue(GuitarTuning.positions(forMIDI: 64, fretCount: 12).allSatisfy { $0.fret <= 12 })
        XCTAssertTrue(GuitarTuning.positions(forMIDI: 200).isEmpty)
    }
}
