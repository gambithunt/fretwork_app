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

    /// The iOS low-E bug report: a weak/absent fundamental with strong 2nd/3rd
    /// harmonics must still resolve to E2 at 48 kHz — the difference function
    /// must find the common period of the harmonics, not a harmonic or a
    /// detuned neighbour.
    func testLowEWithWeakAndAbsentFundamental() {
        for fundamental in [0.0, 0.01, 0.1, 0.3] {
            var samples = [Float](repeating: 0, count: 2048)
            for i in 0..<2048 {
                var v = fundamental * sin(2 * .pi * 82.41 * Double(i) / sampleRate)
                v += 1.0 * sin(2 * .pi * 2 * 82.41 * Double(i) / sampleRate)
                v += 0.7 * sin(2 * .pi * 3 * 82.41 * Double(i) / sampleRate)
                v += 0.4 * sin(2 * .pi * 4 * 82.41 * Double(i) / sampleRate)
                samples[i] = Float(v)
            }
            let result = PitchDetector().detect(samples: samples, sampleRate: sampleRate)
            XCTAssertNotNil(result, "fundamental amplitude \(fundamental)")
            let cents = 1200 * log2(result!.frequency / 82.41)
            XCTAssertLessThanOrEqual(abs(cents), 5.0, "fundamental \(fundamental): measured \(result!.frequency) Hz")
        }
    }

    /// The low-frequency cutoff boost: a real low string decays fast and its
    /// CMNDF at the true period sits above the fixed 0.12 cutoff (measured
    /// ≈0.15 on an unplugged electric E2), so the fixed cutoff produced no
    /// candidate at all. An inharmonic partial raises the CMNDF at tau=582
    /// to ≈0.138 — above the 0.12 base but below the boosted cutoff — and must
    /// still resolve to E2 at the default threshold.
    func testLowFrequencyBoostDetectsMarginalLowE() {
        var samples = [Float](repeating: 0, count: 2048)
        for i in 0..<2048 {
            let v = sin(2 * .pi * 82.41 * Double(i) / sampleRate)
                + 0.3 * sin(2 * .pi * 2.5 * 82.41 * Double(i) / sampleRate)
            samples[i] = Float(v)
        }
        let result = PitchDetector().detect(samples: samples, sampleRate: sampleRate, threshold: 0.12)
        XCTAssertNotNil(result)
        let cents = 1200 * log2(result!.frequency / 82.41)
        // The inharmonic partial pulls the estimate a few cents; the point is
        // that it still resolves to E2 rather than a harmonic or neighbour.
        XCTAssertLessThanOrEqual(abs(cents), 15.0, "measured \(result!.frequency) Hz")
        // Marginal: confidence ≈ 0.86, i.e. CMNDF ≈ 0.14, which a uniform
        // 0.12 cutoff would reject — the boost is what admits it.
        XCTAssertLessThan(result!.confidence, 0.95)
    }
}
