import XCTest
@testable import Fretwork

final class ChordDetectorTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let windowSize = 8192

    private func chordSamples(midiNotes: [Int]) -> [Float] {
        (0..<windowSize).map { sample in
            let t = Double(sample) / sampleRate
            let value = midiNotes.reduce(0.0) { total, midi in
                let frequency = 440 * pow(2, Double(midi - 69) / 12)
                return total + sin(2 * .pi * frequency * t)
            }
            return Float(value / Double(midiNotes.count))
        }
    }

    func testOpenDMajorIsRecognized() {
        // D3 A3 D4 F#4 A4 D5 — the notes an open D chord actually rings.
        let detector = ChordDetector(windowSize: windowSize)
        let samples = chordSamples(midiNotes: [50, 57, 62, 66, 69, 74])
        let match = detector.detect(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(match?.root, "D")
        XCTAssertEqual(match?.quality, .major)
    }

    func testAMinorIsRecognized() {
        // A2 E3 A3 C4 E4 — an open Am chord.
        let detector = ChordDetector(windowSize: windowSize)
        let samples = chordSamples(midiNotes: [45, 52, 57, 60, 64])
        let match = detector.detect(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(match?.root, "A")
        XCTAssertEqual(match?.quality, .minor)
    }

    func testGMajorSevenIsRecognized() {
        // G2 B2 D3 F#3 — root, third, fifth, major seventh.
        let detector = ChordDetector(windowSize: windowSize)
        let samples = chordSamples(midiNotes: [43, 47, 50, 54])
        let match = detector.detect(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(match?.root, "G")
        XCTAssertEqual(match?.quality, .majorSeventh)
    }

    func testSilenceHasNoMatch() {
        let detector = ChordDetector(windowSize: windowSize)
        let samples = [Float](repeating: 0, count: windowSize)
        XCTAssertNil(detector.detect(samples: samples, sampleRate: sampleRate))
    }

    func testMismatchedWindowSizeHasNoMatch() {
        let detector = ChordDetector(windowSize: windowSize)
        XCTAssertNil(detector.detect(samples: [Float](repeating: 0, count: 512), sampleRate: sampleRate))
    }
}
