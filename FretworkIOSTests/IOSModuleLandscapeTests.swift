import XCTest
@testable import Fretwork

/// Covers the pure logic extracted into the iOS module landscape scaffold:
/// the run-subtitle decision (D-27, revised) and the subtitle/step wording.
final class IOSModuleLandscapeTests: XCTestCase {
    // MARK: - Run subtitle (D-27, revised)

    func testSubtitleIsUnchangedWhenNotRunning() {
        XCTAssertEqual(
            IOSModuleRunDecision.subtitle(normal: "A minor pentatonic · Box 1 of 5", stepText: "Next: A · Low E string fret 5", isRunActive: false),
            "A minor pentatonic · Box 1 of 5"
        )
    }

    func testSubtitleShowsTheNextStepWhileRunning() {
        XCTAssertEqual(
            IOSModuleRunDecision.subtitle(normal: "A minor pentatonic · Box 1 of 5", stepText: "Next: A · Low E string fret 5", isRunActive: true),
            "Next: A · Low E string fret 5"
        )
    }

    func testSubtitleFallsBackWhenRunningHasNoStepYet() {
        // The count-in's first beat has no step text, so the subtitle slot
        // keeps its normal text rather than going blank.
        XCTAssertEqual(
            IOSModuleRunDecision.subtitle(normal: "C major · Ascending", stepText: "", isRunActive: true),
            "C major · Ascending"
        )
    }

    func testRunToggleFlipsTheStartButtonToStopInPlace() {
        let idle = IOSModuleBandAction.runToggle(
            title: "Practise", accessibilityLabel: "Practise", isRunActive: false,
            disabled: false, start: {}, stop: {}
        )
        XCTAssertEqual(idle.title, "Practise")
        XCTAssertEqual(idle.systemImage, "play.fill")

        let running = IOSModuleBandAction.runToggle(
            title: "Practise", accessibilityLabel: "Practise", isRunActive: true,
            disabled: false, start: {}, stop: {}
        )
        XCTAssertEqual(running.title, "Stop")
        XCTAssertEqual(running.systemImage, "stop.fill")
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

    // MARK: - Triads

    func testTriadsShapeSubtitleNamesChordAndInversion() {
        XCTAssertEqual(
            IOSModuleLandscapeFormat.triadsShapeSubtitle(root: PitchClass(0), name: "Major", inversion: "1st inversion"),
            "C major · 1st inversion"
        )
    }

    func testTriadsShapeSubtitleOmitsInversionForDoubleStops() {
        XCTAssertEqual(
            IOSModuleLandscapeFormat.triadsShapeSubtitle(root: PitchClass(5), name: "Major 3rds", inversion: nil),
            "F major 3rds"
        )
    }

    func testTriadsPathSubtitleNamesChordDegreeAndStep() {
        XCTAssertEqual(
            IOSModuleLandscapeFormat.triadsPathSubtitle(chord: "C major", roman: "I", index: 2, count: 7),
            "C major · I · 3 of 7"
        )
    }

    func testTriadsPathStepTextNamesNextChordOnItsLowestString() {
        // Two tones, the lowest deliberately *second* so the assertion proves
        // the formatter picks by pitch, not by array order. midiNote and
        // pitchClass stay consistent: 52 = E4, 48 = C3.
        let higher = VoicingTone(
            interval: 4,
            degree: "3",
            position: VoicingPosition(string: 0, fret: 12, midiNote: 52, pitchClass: PitchClass(4))
        )
        let lower = VoicingTone(
            interval: 0,
            degree: "1",
            position: VoicingPosition(string: 1, fret: 3, midiNote: 48, pitchClass: PitchClass(0))
        )
        let voicing = CompactVoicing(
            id: "test",
            tones: [higher, lower],
            minFret: 3,
            maxFret: 12,
            stringSet: "E–A–D",
            inversion: "Root position"
        )
        let chord = DiatonicChord(
            degree: 0,
            roman: "I",
            quality: "maj",
            name: "C major",
            root: PitchClass(0),
            pitchClasses: [],
            intervals: [0, 4, 7],
            degrees: ["1", "3", "5"]
        )
        let step = TriadPathStep(id: "test", chord: chord, voicing: voicing)
        XCTAssertEqual(
            IOSModuleLandscapeFormat.triadsPathStepText(next: step),
            "Next: C major · A string fret 3"
        )
    }

    // MARK: - Scales

    func testScalesSubtitleNamesTheScaleAndDirection() {
        // Scales has no positions; the subtitle says what the shape is and
        // which way a Practise run walks it (D-26).
        XCTAssertEqual(
            IOSModuleLandscapeFormat.scalesSubtitle(scaleName: "C major", direction: .ascending),
            "C major · Ascending"
        )
        XCTAssertEqual(
            IOSModuleLandscapeFormat.scalesSubtitle(scaleName: "A natural minor", direction: .upDown),
            "A natural minor · Up and down"
        )
    }

    func testHarmonizingSubtitleNamesTheChordOfTheKey() {
        // The example D-26 uses: the ii chord of C major.
        XCTAssertEqual(
            IOSModuleLandscapeFormat.harmonizingSubtitle(roman: "ii", chordName: "D minor"),
            "ii · D minor"
        )
    }

    func testNoteAssociationSubtitleNamesTheChordUnderneath() {
        XCTAssertEqual(
            IOSModuleLandscapeFormat.noteAssociationSubtitle(roman: "V", chordName: "G"),
            "Over V · G"
        )
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

    // MARK: - Portrait strip (D-06/D-18)

    func testFocusFretPicksTheLowestOutlinedDot() {
        let dots = [
            FretboardDot(id: "a", position: FretPosition(string: 0, fret: 7), label: "1", color: .white, outline: true),
            FretboardDot(id: "b", position: FretPosition(string: 1, fret: 5), label: "1", color: .white, outline: true),
            FretboardDot(id: "c", position: FretPosition(string: 2, fret: 3), label: "1", color: .white)
        ]
        XCTAssertEqual(IOSModulePortraitStrip.focusFret(for: dots, highestFret: 15), 5)
    }

    func testFocusFretFallsBackToAllDotsWhenNothingIsOutlined() {
        let dots = [
            FretboardDot(id: "a", position: FretPosition(string: 0, fret: 9), label: "1", color: .white),
            FretboardDot(id: "b", position: FretPosition(string: 1, fret: 4), label: "1", color: .white)
        ]
        XCTAssertEqual(IOSModulePortraitStrip.focusFret(for: dots, highestFret: 12), 4)
    }

    func testFocusFretIsZeroWithNoDotsAndClampsToTheBoard() {
        XCTAssertEqual(IOSModulePortraitStrip.focusFret(for: [], highestFret: 12), 0)
        let pastEnd = [FretboardDot(id: "a", position: FretPosition(string: 0, fret: 20), label: "1", color: .white, outline: true)]
        XCTAssertEqual(IOSModulePortraitStrip.focusFret(for: pastEnd, highestFret: 12), 12)
    }

    func testStripGeometryAndScrollOffset() {
        XCTAssertEqual(IOSModulePortraitStrip.width(for: 12), 62 + 44 * 13)
        XCTAssertEqual(IOSModulePortraitStrip.leadingEdge(ofFret: 3, frets: 12), 62 + 44 * 3)
        // A mid fret scrolls so the shape sits just right of the pinned gutter,
        // with the board's own (scrolled-out) gutter and a little context gone.
        XCTAssertEqual(IOSModulePortraitStrip.scrollOffset(for: 2, frets: 12, viewportWidth: 390), 44 * 2 - 20)
        // Near the end it clamps to the last page rather than overshooting.
        XCTAssertEqual(IOSModulePortraitStrip.scrollOffset(for: 12, frets: 12, viewportWidth: 390), 634 - 390)
        // A viewport wider than the strip needs no scroll.
        XCTAssertEqual(IOSModulePortraitStrip.scrollOffset(for: 3, frets: 12, viewportWidth: 700), 0)
    }
}
