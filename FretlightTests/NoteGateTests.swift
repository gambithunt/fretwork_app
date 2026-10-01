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
        XCTAssertEqual(sensitivity(0).floorMarginDb, 14, accuracy: 0.001)
        XCTAssertEqual(sensitivity(0.5).floorMarginDb, 11, accuracy: 0.001)
        XCTAssertEqual(sensitivity(1).floorMarginDb, 8, accuracy: 0.001)
        for value in stride(from: 0.0, through: 1.0, by: 0.1) {
            let s = sensitivity(value)
            XCTAssertLessThan(s.sustainConfidenceThreshold, s.confidenceThreshold)
        }
    }

    /// A quiet note at floor level is rejected by the level gate even when
    /// confidence is high — this is the phantom-note (pitched room noise) rule.
    func testQuietCandidateIsRejectedByLevelGate() {
        let s = sensitivity(0.5) // floor margin 11 dB, conf gate 0.78
        let decision = NoteGate.decide(
            candidateMIDI: 40, confidence: 0.95, lastMIDI: nil,
            levelDb: -55, floorDb: -64, sensitivity: s
        )
        XCTAssertFalse(decision.accepted)
    }

    /// The same candidate clearly above the floor is accepted.
    func testCandidateAboveFloorIsAccepted() {
        let s = sensitivity(0.5)
        let decision = NoteGate.decide(
            candidateMIDI: 40, confidence: 0.95, lastMIDI: nil,
            levelDb: -40, floorDb: -64, sensitivity: s
        )
        XCTAssertTrue(decision.accepted)
        XCTAssertFalse(decision.isContinuation)
    }

    /// A continuation of the confirmed note is held at the relaxed confidence
    /// floor and is exempt from the level gate, so a decaying note does not
    /// drop to "none" when its level or confidence dips.
    func testContinuationHoldsBelowFullGates() {
        let s = sensitivity(0.5) // conf 0.78, sustain 0.63
        let decision = NoteGate.decide(
            candidateMIDI: 40, confidence: 0.70, lastMIDI: 40,
            levelDb: -60, floorDb: -64, sensitivity: s
        )
        XCTAssertTrue(decision.accepted)
        XCTAssertTrue(decision.isContinuation)
    }

    /// A changed pitch re-enters at the full confidence gate: below it, the
    /// change is rejected rather than silently held against the old note.
    func testNoteChangeRequiresFullConfidence() {
        let s = sensitivity(0.5)
        let decision = NoteGate.decide(
            candidateMIDI: 45, confidence: 0.70, lastMIDI: 40,
            levelDb: -40, floorDb: -64, sensitivity: s
        )
        XCTAssertFalse(decision.accepted)
        XCTAssertFalse(decision.isContinuation)
    }

    /// A changed pitch with enough confidence passes the full gate.
    func testNoteChangeWithConfidenceIsAccepted() {
        let s = sensitivity(0.5)
        let decision = NoteGate.decide(
            candidateMIDI: 45, confidence: 0.95, lastMIDI: 40,
            levelDb: -40, floorDb: -64, sensitivity: s
        )
        XCTAssertTrue(decision.accepted)
        XCTAssertFalse(decision.isContinuation)
    }

    /// No candidate (nil MIDI) is always rejected.
    func testNilCandidateIsRejected() {
        let decision = NoteGate.decide(
            candidateMIDI: nil, confidence: 0.99, lastMIDI: 40,
            levelDb: -20, floorDb: -64, sensitivity: sensitivity(0.5)
        )
        XCTAssertFalse(decision.accepted)
        XCTAssertFalse(decision.isContinuation)
    }
}
