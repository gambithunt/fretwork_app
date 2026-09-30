import XCTest
@testable import Fretwork

/// Unit tests for the two pure decisions the Phase 7 speaker-bleed probe
/// rests on: decay-tail detection from a level series against a noise floor,
/// and false-credit detection (did the detector report the *played* pitch
/// class / chord, for how long).
final class BleedProbeAnalysisTests: XCTestCase {

    // MARK: - Decay tail

    func testDecayTailIsZeroWhenQuietAndSilentFromTheEnd() {
        let tail = BleedProbeAnalysis.decayTail(
            noiseFloor: 0.001,
            levelReadings: [.init(time: 1.2, level: 0.001)],
            activeReadings: [.init(time: 1.2, active: false),
                              .init(time: 1.4, active: false)],
            nominalEnd: 1.0
        )
        XCTAssertEqual(tail, 0.0, accuracy: 0.0001)
    }

    func testDecayTailUsesTheLastLoudOrActiveReading() {
        let levels = [
            BleedProbeAnalysis.LevelReading(time: 2.5, level: 0.002), // loud past the threshold
        ]
        let active = [
            BleedProbeAnalysis.ActiveReading(time: 1.5, active: true),
            BleedProbeAnalysis.ActiveReading(time: 1.6, active: false),
        ]
        let tail = BleedProbeAnalysis.decayTail(
            noiseFloor: 0.001,
            levelReadings: levels,
            activeReadings: active,
            nominalEnd: 1.0
        )
        // Last violation is the loud reading at 2.5 → tail 1.5.
        XCTAssertEqual(tail, 1.5, accuracy: 0.0001)
    }

    func testDecayTailIgnoresViolationsBeforeTheNominalEnd() {
        let levels = [
            BleedProbeAnalysis.LevelReading(time: 0.8, level: 0.5),
        ]
        let active = [
            BleedProbeAnalysis.ActiveReading(time: 0.9, active: true),
        ]
        let tail = BleedProbeAnalysis.decayTail(
            noiseFloor: 0.001,
            levelReadings: levels,
            activeReadings: active,
            nominalEnd: 1.0
        )
        XCTAssertEqual(tail, 0.0, accuracy: 0.0001)
    }

    func testTailThresholdIsThreeDBAboveTheFloorAndExclusive() {
        let floor: Float = 0.001
        let threshold = BleedProbeAnalysis.tailThreshold(noiseFloor: floor)
        XCTAssertEqual(Double(threshold), Double(floor) * pow(10, 3.0 / 20.0), accuracy: 0.000_001)

        // A reading exactly at the threshold is not a violation…
        let atThreshold = BleedProbeAnalysis.decayTail(
            noiseFloor: floor,
            levelReadings: [.init(time: 1.5, level: threshold)],
            activeReadings: [],
            nominalEnd: 1.0
        )
        XCTAssertEqual(atThreshold, 0.0, accuracy: 0.0001)

        // …while one epsilon above it is.
        let above = BleedProbeAnalysis.decayTail(
            noiseFloor: floor,
            levelReadings: [.init(time: 1.5, level: threshold + 0.000_001)],
            activeReadings: [],
            nominalEnd: 1.0
        )
        XCTAssertEqual(above, 0.5, accuracy: 0.0001)
    }

    // MARK: - False credit (note pitch class)

    func testFalseCreditSumsEachHeldMatchingReading() {
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 1.0, midiNote: 52),  // E, pc 4 → match
            BleedProbeAnalysis.NoteReading(time: 1.2, midiNote: 53),  // F → no match
            BleedProbeAnalysis.NoteReading(time: 1.4, midiNote: 76),  // E, pc 4 → match
            BleedProbeAnalysis.NoteReading(time: 1.6, midiNote: nil), // silent
            BleedProbeAnalysis.NoteReading(time: 1.8, midiNote: 64),  // E, pc 4 → match
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
        // All three are pitch class 4 (E) in different octaves.
        let readings = [
            BleedProbeAnalysis.NoteReading(time: 1.0, midiNote: 40),  // E2
            BleedProbeAnalysis.NoteReading(time: 1.2, midiNote: 64),  // E4
            BleedProbeAnalysis.NoteReading(time: 1.4, midiNote: 88),  // E6
            BleedProbeAnalysis.NoteReading(time: 1.6, midiNote: 41),  // F2 → no match
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
            BleedProbeAnalysis.NoteReading(time: 0.5, midiNote: 52),
            BleedProbeAnalysis.NoteReading(time: 1.5, midiNote: 52),
            BleedProbeAnalysis.NoteReading(time: 2.5, midiNote: 52),
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
            BleedProbeAnalysis.NoteReading(time: 1.0, midiNote: 50),  // D
            BleedProbeAnalysis.NoteReading(time: 1.2, midiNote: 55),  // G
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

    // MARK: - Noise-floor median

    func testMedianLevelHandlesEvenOddAndEmpty() {
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([1, 2, 3]), 2)
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([]), 0)
        XCTAssertEqual(BleedProbeAnalysis.medianLevel([5, 1, 4, 2, 3]), 3)
        XCTAssertEqual(BleedProbeAnalysis.median([0.2, 0.4, 0.6]), 0.4, accuracy: 0.000_001)
        XCTAssertEqual(BleedProbeAnalysis.median([0.2, 0.4]), 0.3, accuracy: 0.000_001)
    }
}
