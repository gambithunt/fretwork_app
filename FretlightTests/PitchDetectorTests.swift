import XCTest
@testable import Fretwork

final class PitchDetectorTests: XCTestCase {
    private let sampleRate = 48_000.0
    private func sine(_ frequency: Double) -> [Float] {
        (0..<2048).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }
    private func assertPitch(_ frequency: Double, file: StaticString = #filePath, line: UInt = #line) {
        let detector = PitchDetector()
        let result = detector.detect(samples: sine(frequency), sampleRate: sampleRate)
        XCTAssertNotNil(result, file: file, line: line)
        let cents = 1200 * log2(result!.frequency / frequency)
        XCTAssertLessThanOrEqual(abs(cents), 1.0, "\(frequency) Hz measured \(result!.frequency)", file: file, line: line)
    }
    func testOpenStringsAreWithinOneCent() {
        for frequency in [82.41, 110, 146.83, 196, 246.94, 329.63] { assertPitch(frequency) }
    }
    func testOctaveUpDoesNotCollapseAnOctave() { assertPitch(164.81) }
}
