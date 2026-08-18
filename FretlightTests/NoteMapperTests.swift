import XCTest
@testable import Fretwork

final class NoteMapperTests: XCTestCase {
    func testA2MapsToOpenAAndLowE5() {
        let note = NoteMapper.map(frequency: 110)!
        XCTAssertEqual(note.name, "A"); XCTAssertEqual(note.octave, 2); XCTAssertEqual(note.cents, 0, accuracy: 0.01)
        XCTAssertTrue(note.positions.contains(FretPosition(string: 1, fret: 0)))
        XCTAssertTrue(note.positions.contains(FretPosition(string: 0, fret: 5)))
    }
    func testInvalidFrequencyHasNoMapping() { XCTAssertNil(NoteMapper.map(frequency: 0)) }
}
