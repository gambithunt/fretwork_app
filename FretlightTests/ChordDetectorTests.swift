import XCTest
@testable import Fretwork

final class ChordDetectorTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let windowSize = 8192

    private func chordSamples(midiNotes: [Int]) -> [Float] {
        weightedChordSamples(components: midiNotes.map { ($0, 1.0) })
    }

    private func weightedChordSamples(components: [(midi: Int, amplitude: Double)]) -> [Float] {
        (0..<windowSize).map { sample in
            let t = Double(sample) / sampleRate
            let value = components.reduce(0.0) { total, component in
                let frequency = 440 * pow(2, Double(component.midi - 69) / 12)
                return total + component.amplitude * sin(2 * .pi * frequency * t)
            }
            return Float(value / Double(components.count))
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

    /// A *pure* G major triad — nothing else, not even a synthesized 7th —
    /// must read as plain major, not Gmaj7. This is the baseline case
    /// `ChordDetector.complexityMargin` exists for: even with zero F♯
    /// energy actually present, low guitar frequencies leave enough
    /// frequency-resolution smear in the chroma that Gmaj7's template can
    /// win on raw cosine similarity alone. See that constant's doc comment
    /// for the measured scores behind the 0.1 margin.
    func testPureGMajorTriadIsNotMisreadAsMajorSeven() {
        let detector = ChordDetector(windowSize: windowSize)
        let samples = chordSamples(midiNotes: [43, 47, 50]) // G2, B2, D3 — no 7th
        let match = detector.detect(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(match?.root, "G")
        XCTAssertEqual(match?.quality, .major)
    }

    /// A faint F♯ standing in for real harmonic leakage on top of a
    /// full-strength G major triad — quiet enough that it shouldn't yet
    /// read as a deliberately-played 7th.
    func testGMajorWithFaintLeakageStaysPlainMajor() {
        let detector = ChordDetector(windowSize: windowSize)
        let samples = weightedChordSamples(components: [(43, 1.0), (47, 1.0), (50, 1.0), (54, 0.05)]) // G2, B2, D3, F#3(faint)
        let match = detector.detect(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(match?.root, "G")
        XCTAssertEqual(match?.quality, .major)
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
