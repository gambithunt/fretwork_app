#if DEBUG
import XCTest
@testable import Fretwork

final class TakeVerifierTests: XCTestCase {
    private static let rate = 48_000.0
    /// String 1 open is A, MIDI 45, 110 Hz — a convenient known target.
    private static let aString = 1
    private static let aFrequency = 110.0

    private func sine(_ frequency: Double, amplitude: Float = 0.5, seconds: Double = 1, rate: Double = rate) -> [Float] {
        let count = Int(rate * seconds)
        return (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    private func noise(amplitude: Float = 0.5, seconds: Double = 1, rate: Double = rate) -> [Float] {
        var generator = SystemRandomNumberGenerator()
        return (0..<Int(rate * seconds)).map { _ in Float.random(in: -amplitude...amplitude, using: &generator) }
    }

    private func take(_ samples: [Float], rate: Double = rate) -> SampleRecorder.Take {
        SampleRecorder.Take(samples: samples, sampleRate: rate, peak: samples.reduce(0) { max($0, abs($1)) })
    }

    private func cents(from verdict: TakeVerdict) -> Double? {
        switch verdict {
        case let .accepted(_, cents): cents
        case let .wrongPitch(cents): cents
        default: nil
        }
    }

    // MARK: - Verification

    func testAToneAtTheTargetPitchIsAccepted() {
        let verdict = TakeVerifier.verify(take(sine(Self.aFrequency)), string: Self.aString, fret: 0)
        guard case let .accepted(frequency, cents) = verdict else {
            return XCTFail("expected accepted, got \(verdict)")
        }
        XCTAssertEqual(frequency, Self.aFrequency, accuracy: 0.5)
        XCTAssertEqual(cents, 0, accuracy: 2)
    }

    func testAToneThirtyCentsSharpIsRejectedAsWrongPitch() {
        let sharp = Self.aFrequency * pow(2, 30.0 / 1200)
        let verdict = TakeVerifier.verify(take(sine(sharp)), string: Self.aString, fret: 0)
        guard case .wrongPitch = verdict else { return XCTFail("expected wrongPitch, got \(verdict)") }
        XCTAssertEqual(cents(from: verdict) ?? 0, 30, accuracy: 3)
    }

    func testAToneJustInsideTheWindowIsStillAccepted() {
        let flat = Self.aFrequency * pow(2, -5.0 / 1200)
        let verdict = TakeVerifier.verify(take(sine(flat)), string: Self.aString, fret: 0)
        guard case .accepted = verdict else { return XCTFail("expected accepted, got \(verdict)") }
        XCTAssertEqual(cents(from: verdict) ?? 0, -5, accuracy: 3)
    }

    func testAFrettedPositionIsVerifiedAgainstItsOwnPitch() {
        // String 1, fret 5 is D (MIDI 50). The open-string pitch must fail there.
        let d = 440.0 * pow(2, (50.0 - 69) / 12)
        guard case .accepted = TakeVerifier.verify(take(sine(d)), string: Self.aString, fret: 5) else {
            return XCTFail("D at fret 5 should be accepted")
        }
        guard case .wrongPitch = TakeVerifier.verify(take(sine(Self.aFrequency)), string: Self.aString, fret: 5) else {
            return XCTFail("open A at fret 5 should be rejected")
        }
    }

    func testNoiseIsRejectedAsNoStablePitchRatherThanWrongPitch() {
        XCTAssertEqual(TakeVerifier.verify(take(noise()), string: Self.aString, fret: 0), .noStablePitch)
    }

    /// Silence trips the level guard first, which is the more precise verdict:
    /// there is nothing to judge, rather than something unpitched.
    func testSilenceIsRejectedAsTooQuiet() {
        let silent = [Float](repeating: 0, count: Int(Self.rate))
        XCTAssertEqual(TakeVerifier.verify(take(silent), string: Self.aString, fret: 0), .tooQuiet)
    }

    /// Derived from the constant rather than hardcoded, so tuning the
    /// threshold against a real instrument does not quietly invalidate the
    /// test that guards it.
    func testATakeBelowUsableLevelIsRejectedAsTooQuiet() {
        let tooQuiet = TakeVerifier.minimumPeak / 3
        XCTAssertEqual(
            TakeVerifier.verify(take(sine(Self.aFrequency, amplitude: tooQuiet)), string: Self.aString, fret: 0),
            .tooQuiet
        )
        // Just above it must not be rejected for level.
        let audible = TakeVerifier.minimumPeak * 3
        XCTAssertNotEqual(
            TakeVerifier.verify(take(sine(Self.aFrequency, amplitude: audible)), string: Self.aString, fret: 0),
            .tooQuiet
        )
    }

    /// The one case a plain sine cannot catch: if verification analysed from
    /// sample zero, this take's inharmonic opening would sink it.
    func testVerificationJudgesTheSustainNotTheAttack() {
        let attack = noise(amplitude: 0.9, seconds: TakeVerifier.attackSkipSeconds)
        let body = sine(Self.aFrequency, seconds: 1)
        let verdict = TakeVerifier.verify(take(attack + body), string: Self.aString, fret: 0)
        guard case .accepted = verdict else { return XCTFail("expected accepted, got \(verdict)") }
    }

    // MARK: - Trim and normalise

    func testTrimmingReducesLeadingSilenceToTheMarginWithoutTouchingTheNote() {
        let lead = [Float](repeating: 0, count: Int(Self.rate * 0.5))
        let body = sine(Self.aFrequency, seconds: 0.5)
        let trimmed = TakeVerifier.trimmed(take(lead + body))
        let expectedLead = Int(Self.rate * TakeVerifier.preOnsetSeconds)
        XCTAssertEqual(trimmed.samples.count, expectedLead + body.count, accuracy: 64)
        XCTAssertEqual(trimmed.peak, take(body).peak, accuracy: 0.001)
    }

    func testTrimmingATakeThatAlreadyStartsAtItsOnsetChangesNothing() {
        let original = take(sine(Self.aFrequency, seconds: 0.2))
        XCTAssertEqual(TakeVerifier.trimmed(original).samples.count, original.samples.count)
    }

    func testNormalisingSetsThePeakAndPreservesTheWaveformShape() {
        let original = take(sine(Self.aFrequency, amplitude: 0.3, seconds: 0.1))
        let normalized = TakeVerifier.normalized(original)
        XCTAssertEqual(normalized.peak, TakeVerifier.normalizedPeak, accuracy: 0.001)
        XCTAssertEqual(normalized.samples.reduce(0) { max($0, abs($1)) }, TakeVerifier.normalizedPeak, accuracy: 0.001)

        let scale = TakeVerifier.normalizedPeak / original.peak
        for index in stride(from: 0, to: original.samples.count, by: 97) {
            XCTAssertEqual(normalized.samples[index], original.samples[index] * scale, accuracy: 0.0001)
        }
    }

    // MARK: - Regression

    /// `PitchDetector` sized its scratch buffer from `maxTau` rather than from
    /// the window, so any window larger than its 2048-sample initial capacity
    /// had vDSP writing past the end of it. Verification analyses 4096 samples,
    /// which is exactly the case that used to corrupt the heap.
    func testPitchDetectorHandlesWindowsLargerThanItsInitialCapacity() {
        let detector = PitchDetector()
        for count in [2048, 4096, 16_384] {
            let samples = Array(sine(Self.aFrequency, seconds: Double(count) / Self.rate).prefix(count))
            let detection = detector.detect(samples: samples, sampleRate: Self.rate)
            XCTAssertEqual(detection?.frequency ?? 0, Self.aFrequency, accuracy: 1, "window \(count)")
        }
    }
}

private func XCTAssertEqual(_ lhs: Int, _ rhs: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(lhs - rhs), accuracy, "\(lhs) vs \(rhs)", file: file, line: line)
}
#endif
