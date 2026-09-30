import XCTest
@testable import Fretwork

/// Pure timing tests for the playback gate: single play, overlapping plays,
/// the tail edge, and the closed→open ("reset on lift") transition — all with
/// an explicit injected time rather than a real clock.
final class PlaybackGateTests: XCTestCase {

    func testSinglePlaySuppressesThroughNominalEndPlusTail() {
        var gate = PlaybackGate(tail: 0.150)
        XCTAssertEqual(gate.recordPlay(duration: 1.0, at: 0.0), .closed)

        XCTAssertTrue(gate.isSuppressed)
        XCTAssertEqual(gate.update(at: 0.5), .none, "still inside the sample")
        XCTAssertEqual(gate.update(at: 1.0), .none, "still inside the tail")
        XCTAssertEqual(gate.update(at: 1.149), .none, "one tick before the edge")

        // The edge itself is open: suppression is `now < end`, so end is free.
        XCTAssertEqual(gate.update(at: 1.150), .opened)
        XCTAssertFalse(gate.isSuppressed)
        XCTAssertEqual(gate.update(at: 1.151), .none, "already open")
    }

    func testOverlappingPlaysExtendToTheLatestEnd() {
        var gate = PlaybackGate(tail: 0.150)
        gate.recordPlay(duration: 1.0, at: 0.0)   // ends 1.15
        gate.recordPlay(duration: 1.0, at: 0.5)   // extends to 1.65

        XCTAssertEqual(gate.update(at: 1.6), .none, "still inside the extended window")
        XCTAssertTrue(gate.isSuppressed)
        XCTAssertEqual(gate.update(at: 1.65), .opened, "the later play's tail edge wins")
        XCTAssertFalse(gate.isSuppressed)
    }

    func testResetOnLiftTransitionFiresExactlyOnce() {
        var gate = PlaybackGate(tail: 0.0)
        gate.recordPlay(duration: 0.5, at: 0.0)

        XCTAssertEqual(gate.update(at: 0.4), .none)
        XCTAssertEqual(gate.update(at: 0.5), .opened)
        XCTAssertEqual(gate.update(at: 0.6), .none, "the lift transition is edge-triggered, not level")
    }

    func testRecordPlayReturnsClosedOnlyWhenOpeningFromAnOpenState() {
        var gate = PlaybackGate(tail: 0.150)
        XCTAssertEqual(gate.recordPlay(duration: 1.0, at: 0.0), .closed)
        // A second play while already suppressed is not a fresh close.
        XCTAssertEqual(gate.recordPlay(duration: 1.0, at: 0.5), .none)

        // Let it fully open, then a new play closes it again.
        _ = gate.update(at: 10.0)
        XCTAssertEqual(gate.recordPlay(duration: 1.0, at: 10.0), .closed)
    }
}
