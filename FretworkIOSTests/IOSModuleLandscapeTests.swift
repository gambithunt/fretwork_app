import XCTest
@testable import Fretwork

/// Covers the pure logic extracted into the iOS module landscape scaffold:
/// the band-mode decision (D-27) and the subtitle/step wording.
final class IOSModuleLandscapeTests: XCTestCase {
    // MARK: - Band mode (D-27)

    func testBandModeIsNormalWhenGuidedSessionIsIdle() {
        XCTAssertEqual(
            IOSModuleBandDecision.mode(guidedStatus: GuidedSession<GuidedScaleStep>.Status.idle),
            .normal
        )
    }

    func testBandModeIsGuidedRunDuringCountIn() {
        // The player has committed once the count-in starts; the drawer must
        // already be out of reach.
        XCTAssertEqual(
            IOSModuleBandDecision.mode(guidedStatus: GuidedSession<GuidedScaleStep>.Status.countIn),
            .guidedRun
        )
    }

    func testBandModeIsGuidedRunWhilePlaying() {
        XCTAssertEqual(
            IOSModuleBandDecision.mode(guidedStatus: GuidedSession<GuidedScaleStep>.Status.playing),
            .guidedRun
        )
    }

    // MARK: - Subtitles

    func testIntervalSubtitleNamesTheIntervalAndItsDistance() {
        let majorThird = Intervals.all.first { $0.short == "M3" }!
        XCTAssertEqual(IOSModuleLandscapeFormat.intervalSubtitle(majorThird), "Major 3rd · 4 frets")

        let octave = Intervals.all.first { $0.short == "P8" }!
        XCTAssertEqual(IOSModuleLandscapeFormat.intervalSubtitle(octave), "Octave · 12 frets")
    }

    func testChordsPositionSubtitleIncludesPlaceInVoicingList() {
        XCTAssertEqual(
            IOSModuleLandscapeFormat.chordsPositionSubtitle(positionLabel: "Open", positionIndex: 0, voicingCount: 5),
            "Open · 1 of 5"
        )
        XCTAssertEqual(
            IOSModuleLandscapeFormat.chordsPositionSubtitle(positionLabel: "Fret 5", positionIndex: 2, voicingCount: 4),
            "Fret 5 · 3 of 4"
        )
    }

    func testChordsPositionSubtitleFallsBackToPositionLabelWhenIndexMissing() {
        XCTAssertEqual(
            IOSModuleLandscapeFormat.chordsPositionSubtitle(positionLabel: "Open", positionIndex: nil, voicingCount: 5),
            "Open"
        )
    }

    func testPentatonicSubtitleNamesScaleAndBox() {
        // A minor, box 0 -> displayed as "Box 1 of 5".
        XCTAssertEqual(
            IOSModuleLandscapeFormat.pentatonicSubtitle(
                root: PitchClass(9),
                quality: .minorPentatonic,
                box: 0
            ),
            "A minor pentatonic · Box 1 of 5"
        )

        XCTAssertEqual(
            IOSModuleLandscapeFormat.pentatonicSubtitle(
                root: PitchClass(0),
                quality: .majorPentatonic,
                box: 4
            ),
            "C major pentatonic · Box 5 of 5"
        )
    }

    func testCircleSubtitleNamesTheSelectedMajorKey() {
        XCTAssertEqual(IOSModuleLandscapeFormat.circleSubtitle(PitchClass(7)), "G major")
        XCTAssertEqual(IOSModuleLandscapeFormat.circleSubtitle(PitchClass(10)), "A♯ major")
    }

    // MARK: - Notes

    func testNotesPlacedSubtitleCountsCorrectly() {
        XCTAssertEqual(IOSModuleLandscapeFormat.notesPlacedSubtitle(count: 0), "No notes placed")
        XCTAssertEqual(IOSModuleLandscapeFormat.notesPlacedSubtitle(count: 1), "1 note placed")
        XCTAssertEqual(IOSModuleLandscapeFormat.notesPlacedSubtitle(count: 4), "4 notes placed")
    }

    // MARK: - Octaves

    func testOctavesPositionSubtitleNamesPlaceInTheList() {
        XCTAssertEqual(IOSModuleLandscapeFormat.octavesPositionSubtitle(index: 0, count: 5), "Position 1 of 5")
        XCTAssertEqual(IOSModuleLandscapeFormat.octavesPositionSubtitle(index: 4, count: 5), "Position 5 of 5")
    }

    func testOctavesPositionSubtitleFallsBackWhenNoAnchor() {
        XCTAssertEqual(IOSModuleLandscapeFormat.octavesPositionSubtitle(index: nil, count: 5), "Position —")
    }

    // MARK: - Guided-run step text (D-27)

    func testGuidedRunStepTextNamesNoteStringAndFret() {
        // D on the B string, fret 3 — the exact example D-27 uses.
        let step = GuidedScaleStep(
            id: "test",
            string: 4,
            fret: 3,
            midiNote: 62,
            pitchClass: PitchClass(2),
            degree: "♭3",
            finger: .index
        )
        XCTAssertEqual(
            IOSModuleLandscapeFormat.guidedRunStepText(next: step),
            "Next: D · B string fret 3"
        )
    }

    func testGuidedRunStepTextQualifiesTheOuterStrings() {
        // Standard tuning names the outer strings "Low E" / "High E".
        let lowE = GuidedScaleStep(
            id: "low", string: 0, fret: 0, midiNote: 40, pitchClass: PitchClass(4), degree: "1", finger: .open
        )
        XCTAssertEqual(
            IOSModuleLandscapeFormat.guidedRunStepText(next: lowE),
            "Next: E · Low E string fret 0"
        )
    }
}
