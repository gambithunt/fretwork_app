import XCTest
@testable import Fretwork

/// Unit tests for the pure decisions the Phase 7 speaker-bleed probe rests on:
/// the detector-based tail (last fresh detection after a sample's nominal end),
/// false-credit detection (did the detector report the *played* pitch class /
/// chord, for how long), other-pitch-class misreads, and the summary
/// statistics.
final class BleedProbeAnalysisTests: XCTestCase {

    // MARK: - Detector-based tail

    func testLastDetectionAfterEndUsesConfidenceNotTheHold() {
        let readings = [
            // Fresh detection (confidence > 0) at 1.3 s after end.
            BleedProbeAnalysis.NoteReading(time: 11.3, midiNote: 64, confidence: 0.9),
            // Hold frames: note still non-nil but confidence 0 — must not count.
            BleedProbeAnalysis.NoteReading(time: 11.4, midiNote: 64, confidence: 0),
            BleedProbeAnalysis.NoteReading(time: 11.5, midiNote: 64, confidence: 0),
        ]
        let last = BleedProbeAnalysis.lastDetectionAfterEnd(
            readings: readings,
            nominalEnd: 10.0,
            gapEnd: 18.0
        )
        XCTAssertEqual(last ?? -1, 1.3, accuracy: 0.0001)
    }

    func testLastDetectionAfterEndIsNilWhenOnlyTheHoldRemains() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 11.3, midiNote: 64, confidence: 0),
        ]
        XCTAssertNil(BleedProbeAnalysis.lastDetectionAfterEnd(
            readings: readings, nominalEnd: 10.0, gapEnd: 18.0))
    }

    func testLastDetectionAfterEndIgnoresReadingsOutsideTheGap() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 9.0, midiNote: 64, confidence: 0.9),   // before end
            BleedProbeAnalysis.NoteReading(time: 19.0, midiNote: 64, confidence: 0.9),  // past gapEnd
        ]
        XCTAssertNil(BleedProbeAnalysis.lastDetectionAfterEnd(
            readings: readings, nominalEnd: 10.0, gapEnd: 18.0))
    }

    func testLastPlayedPitchAfterEndOnlyCountsThePlayedPitchClass() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 11.0, midiNote: 64, confidence: 0.9),  // E (pc 4) — played
            BleedProbeAnalysis.NoteReading(time: 11.5, midiNote: 55, confidence: 0.9),  // G (pc 7) — other
            BleedProbeAnalysis.NoteReading(time: 12.0, midiNote: 76, confidence: 0.9),  // E octave — played
        ]
        let last = BleedProbeAnalysis.lastPlayedPitchAfterEnd(
            playedPitchClasses: [4],
            readings: readings,
            nominalEnd: 10.0,
            gapEnd: 18.0
        )
        XCTAssertEqual(last ?? -1, 2.0, accuracy: 0.0001)
    }

    func testLastChordDetectionAfterEnd() {
        let readings = [
            BleedProbeAnalysis.ChordReading(time: 11.0, name: "C"),
            BleedProbeAnalysis.ChordReading(time: 12.5, name: nil),
            BleedProbeAnalysis.ChordReading(time: 13.0, name: "C"),
        ]
        let last = BleedProbeAnalysis.lastChordDetectionAfterEnd(
            readings: readings, nominalEnd: 10.0, gapEnd: 18.0)
        XCTAssertEqual(last ?? -1, 3.0, accuracy: 0.0001)
    }

    // MARK: - Other pitch classes (harmonics / misreads)

    func testOtherPitchClassesReturnsSortedNonPlayedClasses() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 10.2, midiNote: 64, confidence: 0.9),  // E → played
            BleedProbeAnalysis.NoteReading(time: 10.4, midiNote: 55, confidence: 0.9),  // G → other
            BleedProbeAnalysis.NoteReading(time: 10.6, midiNote: 71, confidence: 0.9),  // B → other
            BleedProbeAnalysis.NoteReading(time: 10.8, midiNote: 67, confidence: 0.9),  // G octave → other (dup)
            BleedProbeAnalysis.NoteReading(time: 11.0, midiNote: 64, confidence: 0),    // hold → ignored
        ]
        let others = BleedProbeAnalysis.otherPitchClasses(
            playedPitchClasses: [4],
            readings: readings,
            from: 10.0,
            to: 18.0
        )
        XCTAssertEqual(others, [7, 11])  // G and B, deduplicated and sorted.
    }

    // MARK: - False credit (note pitch class)

    func testFalseCreditSumsEachHeldMatchingReading() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 1.0, midiNote: 52, confidence: 0.9),  // E → match
            BleedProbeAnalysis.NoteReading(time: 1.2, midiNote: 53, confidence: 0.9),  // F → no match
            BleedProbeAnalysis.NoteReading(time: 1.4, midiNote: 76, confidence: 0.9),  // E → match
            BleedProbeAnalysis.NoteReading(time: 1.6, midiNote: nil, confidence: 0),   // silent
            BleedProbeAnalysis.NoteReading(time: 1.8, midiNote: 64, confidence: 0),    // hold → match
        ]
        let duration = BleedProbeAnalysis.falseCreditDuration(
            playedPitchClasses: [4],
            readings: readings,
            from: 0,
            to: 2.0
        )
        // 1.0→1.2 (0.2) + 1.4→1.6 (0.2) + 1.8→2.0 (0.2).
        XCTAssertEqual(duration, 0.6, accuracy: 0.0001)
    }

    func testFalseCreditMatchesAnyOctaveOfThePlayedPitchClass() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 1.0, midiNote: 40, confidence: 0.9),  // E2
            BleedProbeAnalysis.NoteReading(time: 1.2, midiNote: 64, confidence: 0.9),  // E4
            BleedProbeAnalysis.NoteReading(time: 1.4, midiNote: 88, confidence: 0.9),  // E6
            BleedProbeAnalysis.NoteReading(time: 1.6, midiNote: 41, confidence: 0.9),  // F2 → no match
        ]
        let duration = BleedProbeAnalysis.falseCreditDuration(
            playedPitchClasses: [4],
            readings: readings,
            from: 0,
            to: 2.0
        )
        XCTAssertEqual(duration, 0.6, accuracy: 0.0001)
    }

    func testFalseCreditIgnoresReadingsOutsideTheWindow() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 0.5, midiNote: 52, confidence: 0.9),
            BleedProbeAnalysis.NoteReading(time: 1.5, midiNote: 52, confidence: 0.9),
            BleedProbeAnalysis.NoteReading(time: 2.5, midiNote: 52, confidence: 0.9),
        ]
        let duration = BleedProbeAnalysis.falseCreditDuration(
            playedPitchClasses: [4],
            readings: readings,
            from: 1.0,
            to: 2.0
        )
        // Only the 1.5 reading, held until the 2.5 reading clamps to `to` (2.0).
        XCTAssertEqual(duration, 0.5, accuracy: 0.0001)
    }

    func testFalseCreditIsZeroWhenThePlayedPitchClassIsNeverReported() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 1.0, midiNote: 50, confidence: 0.9),  // D
            BleedProbeAnalysis.NoteReading(time: 1.2, midiNote: 55, confidence: 0.9),  // G
        ]
        let duration = BleedProbeAnalysis.falseCreditDuration(
            playedPitchClasses: [4],
            readings: readings,
            from: 0,
            to: 2.0
        )
        XCTAssertEqual(duration, 0.0, accuracy: 0.0001)
    }

    // MARK: - False credit (chord name)

    func testChordFalseCreditSumsMatchingNameReadings() {
        let readings = [
            BleedProbeAnalysis.ChordReading(time: 1.0, name: "C"),
            BleedProbeAnalysis.ChordReading(time: 1.2, name: "G"),
            BleedProbeAnalysis.ChordReading(time: 1.5, name: "C"),
        ]
        let duration = BleedProbeAnalysis.chordFalseCreditDuration(
            playedChordName: "C",
            readings: readings,
            from: 0,
            to: 2.0
        )
        // 1.0→1.2 (0.2) + 1.5→2.0 (0.5).
        XCTAssertEqual(duration, 0.7, accuracy: 0.0001)
    }

    // MARK: - Statistics

    func testMedianLevelHandlesEvenOddAndEmpty() {
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([1, 2, 3]), 2)
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([]), 0)
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([5, 1, 4, 2, 3]), 3)
        XCTAssertEqual(BleedProbeAnalysis.median([0.2, 0.4, 0.6]), 0.4, accuracy: 0.000_001)
        XCTAssertEqual(BleedProbeAnalysis.median([0.2, 0.4]), 0.3, accuracy: 0.000_001)
    }

    func testP90UsesLinearInterpolation() {
        XCTAssertEqual(BleedProbeAnalysis.p90([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), 9.1, accuracy: 0.0001)
        XCTAssertEqual(BleedProbeAnalysis.p90([5]), 5, accuracy: 0.0001)
        XCTAssertEqual(BleedProbeAnalysis.p90([]), 0, accuracy: 0.0001)
        // Order does not matter.
        XCTAssertEqual(BleedProbeAnalysis.p90([10, 1, 9, 2, 8, 3, 7, 4, 6, 5]), 9.1, accuracy: 0.0001)
    }
}
