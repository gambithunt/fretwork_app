#if DEBUG
import XCTest
@testable import Fretwork

/// The session log's line shapes are pure formatting, so the exact text the
/// owner reads from `devicectl --console` is pinned here.
final class SessionLogFormatTests: XCTestCase {

    func testNoteLineWithANote() {
        let note = MappedNote(name: "E", octave: 2, midiNote: 40, cents: 3.2)
        XCTAssertEqual(
            SessionLogFormat.noteLine(t: 12.345, note: note, confidence: 0.95, level: 0.008),
            "SESSION t=12.345 note=E2 cents=3.2 conf=0.950 level=-41.9"
        )
    }

    func testNoteLineWithNoNote() {
        XCTAssertEqual(
            SessionLogFormat.noteLine(t: 0.0, note: nil, confidence: 0, level: 0.0005),
            "SESSION t=0.000 note=none cents=- conf=0.000 level=-66.0"
        )
    }

    func testChordGateAndStatusLines() {
        XCTAssertEqual(SessionLogFormat.chordLine(t: 3.0, chord: "C"), "SESSION t=3.000 chord=C")
        XCTAssertEqual(SessionLogFormat.chordLine(t: 3.0, chord: nil), "SESSION t=3.000 chord=none")
        XCTAssertEqual(SessionLogFormat.gateLine(t: 4.0, closed: true), "SESSION t=4.000 gate=closed")
        XCTAssertEqual(SessionLogFormat.gateLine(t: 4.0, closed: false), "SESSION t=4.000 gate=opened")
        XCTAssertEqual(SessionLogFormat.statusLine(t: 5.0, status: .listening), "SESSION t=5.000 status=listening")
        XCTAssertEqual(SessionLogFormat.statusLine(t: 5.0, status: .failed("boom")), "SESSION t=5.000 status=failed:boom")
        XCTAssertEqual(SessionLogFormat.statusLine(t: 5.0, status: nil), "SESSION t=5.000 status=none")
    }

    func testSummaryLineWithAndWithoutLatencies() {
        XCTAssertEqual(
            SessionLogFormat.summaryLine(
                notes: 14,
                distinctPitchClasses: 7,
                onsetMedian: 0.21,
                onsetP90: 0.48,
                noiseFloor: 0.0005
            ),
            "SESSION summary notes=14 distinctPC=7 onsetMedian=0.210 onsetP90=0.480 noiseFloor=-66.0"
        )
        XCTAssertEqual(
            SessionLogFormat.summaryLine(
                notes: 0,
                distinctPitchClasses: 0,
                onsetMedian: nil,
                onsetP90: nil,
                noiseFloor: 0.001
            ),
            "SESSION summary notes=0 distinctPC=0 onsetMedian=- onsetP90=- noiseFloor=-60.0"
        )
    }
}
#endif
