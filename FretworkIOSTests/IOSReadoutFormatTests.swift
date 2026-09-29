import XCTest
@testable import Fretwork

/// The readout formatting/derivation rules are pure: in-tune threshold, cents
/// spelling, silent-state labels and the level meter math, all testable with no
/// view or audio in the process.
@MainActor
final class IOSReadoutFormatTests: XCTestCase {
    func testInTuneBandIsWithinFiveCents() {
        XCTAssertEqual(IOSReadoutFormat.centsTint(0), .inTune)
        XCTAssertEqual(IOSReadoutFormat.centsTint(5), .inTune)
        XCTAssertEqual(IOSReadoutFormat.centsTint(-5), .inTune)
        XCTAssertEqual(IOSReadoutFormat.centsTint(6), .offTune)
        XCTAssertEqual(IOSReadoutFormat.centsTint(-6), .offTune)
        XCTAssertEqual(IOSReadoutFormat.centsTint(nil), .offTune)
    }

    func testCentsSpelling() {
        XCTAssertEqual(IOSReadoutFormat.centsText(8), "+8¢")
        XCTAssertEqual(IOSReadoutFormat.centsText(-3), "-3¢")
        XCTAssertEqual(IOSReadoutFormat.centsText(nil), "—")
    }

    func testSilentLabels() {
        XCTAssertEqual(IOSReadoutFormat.noteLabel(nil), "—")
        XCTAssertEqual(IOSReadoutFormat.chordLabel(nil), "—")
        XCTAssertEqual(IOSReadoutFormat.frequencyText(nil), "—")
    }

    func testNoteAndChordLabels() {
        let note = MappedNote(name: "A", octave: 2, midiNote: 45, cents: 0)
        XCTAssertEqual(IOSReadoutFormat.noteLabel(note), "A2")
        let chord = ChordMatch(root: "A", quality: .minor, confidence: 0.8)
        XCTAssertEqual(IOSReadoutFormat.chordLabel(chord), "Am")
    }

    func testLevelMeterMath() {
        XCTAssertEqual(IOSReadoutFormat.decibels(1), 0, accuracy: 0.001)
        XCTAssertEqual(IOSReadoutFormat.decibels(0), -120, accuracy: 0.001)
        XCTAssertEqual(IOSReadoutFormat.normalizedLevel(1), 1, accuracy: 0.001)
        XCTAssertEqual(IOSReadoutFormat.normalizedLevel(0), 0, accuracy: 0.001)
    }

    func testPulseRespectsReduceMotion() {
        XCTAssertEqual(IOSReadoutFormat.pulseScale(normalizedLevel: 0.5, reduceMotion: false), 1.2, accuracy: 0.001)
        XCTAssertEqual(IOSReadoutFormat.pulseScale(normalizedLevel: 0.5, reduceMotion: true), 1.0, accuracy: 0.001)
        XCTAssertEqual(IOSReadoutFormat.pulseScale(normalizedLevel: 0, reduceMotion: false), 1.0, accuracy: 0.001)
    }
}
