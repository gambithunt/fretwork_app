import XCTest
@testable import Fretwork

/// Pins the leap-vs-blip rules of `NoteConfirmation`, the pure state machine
/// behind `AudioAnalysisWorker`'s per-frame consume loop, without the ring,
/// queue or wall-clock throttling.
final class NoteConfirmationTests: XCTestCase {
    private func confirmA2(_ c: inout NoteConfirmation) {
        // A new note confirms once two candidate frames agree within ±20¢.
        XCTAssertFalse(c.ingest(candidateMIDI: 45, frequency: 110.0,
                                isContinuation: false, confidencePasses: true, levelPasses: true))
        XCTAssertTrue(c.ingest(candidateMIDI: 45, frequency: 110.0,
                               isContinuation: false, confidencePasses: true, levelPasses: true))
        XCTAssertEqual(c.lastMIDI, 45)
    }

    /// A clean stable leap (A2 → E4) moves the frequency readout on the first
    /// changed frame and switches the name only once three of the last five
    /// candidates agree (the 3-of-5 median), keeping the frequency fast and
    /// the name spike-proof.
    func testStableLeapCommitsNameOnMedianMajority() {
        var c = NoteConfirmation()
        confirmA2(&c)

        for _ in 0..<2 {
            let verdict = c.ingest(candidateMIDI: 64, frequency: 329.63,
                                   isContinuation: false, confidencePasses: true, levelPasses: true)
            XCTAssertTrue(verdict, "the frequency readout must move on every changed frame")
            XCTAssertEqual(c.lastMIDI, 45, "the name must not switch before the median majority")
        }

        let third = c.ingest(candidateMIDI: 64, frequency: 329.63,
                             isContinuation: false, confidencePasses: true, levelPasses: true)
        XCTAssertTrue(third)
        XCTAssertEqual(c.lastMIDI, 64)
    }

    /// A one-frame octave spike (E2 → E3 for a single frame) must not switch
    /// the name, even though the frame itself is a valid detection and moves
    /// the frequency readout.
    func testOneFrameOctaveBlipDoesNotSwitchName() {
        var c = NoteConfirmation()
        confirmA2(&c)

        let blip = c.ingest(candidateMIDI: 52, frequency: 164.81,
                            isContinuation: false, confidencePasses: true, levelPasses: true)
        XCTAssertTrue(blip, "the blip is still a real detection")
        XCTAssertEqual(c.lastMIDI, 45)

        let back = c.ingest(candidateMIDI: 45, frequency: 110.0,
                            isContinuation: true, confidencePasses: true, levelPasses: true)
        XCTAssertTrue(back)
        XCTAssertEqual(c.lastMIDI, 45)
    }

    /// Two agreeing octave-below frames (the D2 wobble seen on a decaying D3)
    /// are still only two of five, so the 3-of-5 median must not switch the
    /// name.
    func testTwoFrameOctaveBelowWobbleDoesNotSwitchName() {
        var c = NoteConfirmation()
        confirmA2(&c)

        for _ in 0..<2 {
            let verdict = c.ingest(candidateMIDI: 33, frequency: 55.0,
                                   isContinuation: false, confidencePasses: true, levelPasses: true)
            XCTAssertTrue(verdict, "each wobble frame is still a detection")
            XCTAssertEqual(c.lastMIDI, 45)
        }
    }

    /// A brand-new note still confirms via the ±20¢ stability gate (two
    /// frames), unchanged by the leap rule.
    func testNewNoteStillCommitsAfterTwoStableFrames() {
        var c = NoteConfirmation()
        XCTAssertFalse(c.ingest(candidateMIDI: 64, frequency: 329.63,
                                isContinuation: false, confidencePasses: true, levelPasses: true))
        XCTAssertNil(c.lastMIDI)
        XCTAssertTrue(c.ingest(candidateMIDI: 64, frequency: 329.63,
                               isContinuation: false, confidencePasses: true, levelPasses: true))
        XCTAssertEqual(c.lastMIDI, 64)
    }

    /// A single candidate frame never confirms a brand-new note, so a
    /// one-frame octave/harmonic spike at note onset cannot become a phantom.
    func testNewNoteOneFrameBlipDoesNotCommit() {
        var c = NoteConfirmation()
        let verdict = c.ingest(candidateMIDI: 64, frequency: 329.63,
                               isContinuation: false, confidencePasses: true, levelPasses: true)
        XCTAssertFalse(verdict)
        XCTAssertNil(c.lastMIDI)
    }
}
