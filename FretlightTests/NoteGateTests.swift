import XCTest
@testable import Fretwork

final class NoteGateTests: XCTestCase {
    private func sensitivity(_ value: Double) -> SensitivitySettings {
        let s = SensitivitySettings()
        s.value = value
        return s
    }

    /// The sensitivity dial mapping: margin shrinks as the dial rises, and the
    /// sustain floor always sits below the full confidence gate.
    func testSensitivityDerivedProperties() {
        XCTAssertEqual(sensitivity(0).floorMarginDb, 13, accuracy: 0.001)
        XCTAssertEqual(sensitivity(0.5).floorMarginDb, 10, accuracy: 0.001)
        XCTAssertEqual(sensitivity(1).floorMarginDb, 7, accuracy: 0.001)
        for value in stride(from: 0.0, through: 1.0, by: 0.1) {
            let s = sensitivity(value)
            XCTAssertLessThan(s.sustainConfidenceThreshold, s.confidenceThreshold)
        }
    }

    /// A quiet candidate at floor level fails the level gate even when
    /// confidence is high — the phantom-note (pitched room noise) rule.
    func testQuietCandidateFailsLevelGate() {
        let s = sensitivity(0.5) // floor margin 11 dB, conf gate 0.78
        let d = NoteGate.decide(candidateMIDI: 40, confidence: 0.95, lastMIDI: nil,
                                levelDb: -55, floorDb: -64, sensitivity: s)
        XCTAssertTrue(d.confidencePasses)
        XCTAssertFalse(d.levelPasses)
        XCTAssertFalse(d.isContinuation)
    }

    /// The same candidate clearly above the floor passes both gates.
    func testCandidateAboveFloorPasses() {
        let s = sensitivity(0.5)
        let d = NoteGate.decide(candidateMIDI: 40, confidence: 0.95, lastMIDI: nil,
                                levelDb: -40, floorDb: -64, sensitivity: s)
        XCTAssertTrue(d.confidencePasses)
        XCTAssertTrue(d.levelPasses)
        XCTAssertFalse(d.isContinuation)
    }

    /// A continuation of the confirmed note passes at the relaxed confidence
    /// floor and is level-exempt, so a decaying note doesn't drop.
    func testContinuationHoldsBelowFullGates() {
        let s = sensitivity(0.5) // conf 0.78, sustain 0.63
        let d = NoteGate.decide(candidateMIDI: 40, confidence: 0.70, lastMIDI: 40,
                                levelDb: -60, floorDb: -64, sensitivity: s)
        XCTAssertTrue(d.isContinuation)
        XCTAssertTrue(d.confidencePasses)
        XCTAssertTrue(d.levelPasses)
    }

    /// A changed pitch re-enters at the full confidence gate: below it, the
    /// change is rejected rather than held against the old note.
    func testNoteChangeRequiresFullConfidence() {
        let s = sensitivity(0.5)
        let d = NoteGate.decide(candidateMIDI: 45, confidence: 0.70, lastMIDI: 40,
                                levelDb: -40, floorDb: -64, sensitivity: s)
        XCTAssertFalse(d.isContinuation)
        XCTAssertFalse(d.confidencePasses)
    }

    /// A changed pitch with enough confidence passes the full gate.
    func testNoteChangeWithConfidencePasses() {
        let s = sensitivity(0.5)
        let d = NoteGate.decide(candidateMIDI: 45, confidence: 0.95, lastMIDI: 40,
                                levelDb: -40, floorDb: -64, sensitivity: s)
        XCTAssertFalse(d.isContinuation)
        XCTAssertTrue(d.confidencePasses)
        XCTAssertTrue(d.levelPasses)
    }

    /// No candidate is always rejected.
    func testNilCandidateIsRejected() {
        let d = NoteGate.decide(candidateMIDI: nil, confidence: 0.99, lastMIDI: 40,
                                levelDb: -20, floorDb: -64, sensitivity: sensitivity(0.5))
        XCTAssertFalse(d.isContinuation)
        XCTAssertFalse(d.confidencePasses)
        XCTAssertFalse(d.levelPasses)
    }
}
