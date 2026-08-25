#if DEBUG
import XCTest
@testable import Fretwork

final class SampleLibraryTests: XCTestCase {
    private var directory: URL!
    private var library: SampleLibrary!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fretwork-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        library = SampleLibrary(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func take(peak: Float = 0.5, seconds: Double = 0.05, rate: Double = 48_000) -> SampleRecorder.Take {
        let samples = (0..<Int(rate * seconds)).map { peak * Float(sin(2 * .pi * 110 * Double($0) / rate)) }
        return SampleRecorder.Take(samples: samples, sampleRate: rate, peak: samples.reduce(0) { max($0, abs($1)) })
    }

    @discardableResult
    private func write(string: Int, fret: Int, peak: Float = 0.5) throws -> SampleLibraryEntry {
        try library.write(take: take(peak: peak), string: string, fret: fret, frequency: 110, cents: 0)
    }

    private func audioURL(string: Int, fret: Int) throws -> URL {
        let name = try XCTUnwrap(SampleLibrary.filename(string: string, fret: fret))
        return directory.appendingPathComponent(name)
    }

    // MARK: - Naming

    func testFilenameCarriesStringFretAndMIDIWithLowEAtIndexZero() {
        XCTAssertEqual(SampleLibrary.filename(string: 0, fret: 0), "s0-f00-m040.wav")
        XCTAssertEqual(SampleLibrary.filename(string: 0, fret: 3), "s0-f03-m043.wav")
        XCTAssertEqual(SampleLibrary.filename(string: 5, fret: 22), "s5-f22-m086.wav")
    }

    func testFilenameRefusesAPositionThatDoesNotExist() {
        XCTAssertNil(SampleLibrary.filename(string: 6, fret: 0))
        XCTAssertNil(SampleLibrary.filename(string: 0, fret: 23))
        XCTAssertNil(SampleLibrary.filename(string: -1, fret: 0))
    }

    func testWritingAnImpossiblePositionThrowsRatherThanTrapping() {
        XCTAssertThrowsError(try library.write(take: take(), string: 0, fret: 23, frequency: 110, cents: 0))
    }

    // MARK: - Round trip

    func testEntriesRoundTripThroughTheManifest() throws {
        try write(string: 1, fret: 0)
        try write(string: 2, fret: 7)

        let reopened = SampleLibrary(directory: directory)
        let entries = try reopened.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.string)), [1, 2])
        let a = try XCTUnwrap(entries.first { $0.string == 1 })
        XCTAssertEqual(a.targetMIDI, Tunings.standard.openMIDINotes[1])
        XCTAssertEqual(a.detectedFrequency, 110)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try audioURL(string: 1, fret: 0).path))
    }

    func testAnEmptyDirectoryHasNoEntriesRatherThanFailing() throws {
        XCTAssertEqual(try library.entries().count, 0)
    }

    // MARK: - Resuming a session

    func testMissingPositionsCoversTheWholeNeckAndShrinksAsTakesLand() throws {
        XCTAssertEqual(try library.missingPositions().count, 6 * 23)
        try write(string: 0, fret: 0)
        try write(string: 3, fret: 12)
        let missing = try library.missingPositions()
        XCTAssertEqual(missing.count, 6 * 23 - 2)
        XCTAssertFalse(missing.contains(FretPosition(string: 0, fret: 0)))
        XCTAssertFalse(missing.contains(FretPosition(string: 3, fret: 12)))
        XCTAssertTrue(missing.contains(FretPosition(string: 0, fret: 1)))
    }

    func testReRecordingOnePositionReplacesItAndLeavesTheOthersAlone() throws {
        try write(string: 1, fret: 0, peak: 0.5)
        try write(string: 2, fret: 0, peak: 0.5)
        let firstOther = try XCTUnwrap(try library.entries().first { $0.string == 2 })

        let replaced = try library.write(take: take(peak: 0.4, seconds: 0.08), string: 1, fret: 0, frequency: 220, cents: 4)

        let entries = try library.entries()
        XCTAssertEqual(entries.count, 2, "re-recording must not add a second row for one position")
        XCTAssertEqual(replaced.detectedFrequency, 220)
        XCTAssertEqual(try XCTUnwrap(entries.first { $0.string == 1 }).detectedFrequency, 220)
        XCTAssertEqual(try XCTUnwrap(entries.first { $0.string == 2 }).recordedAt, firstOther.recordedAt)
    }

    // MARK: - Reconciliation

    func testACleanLibraryReportsNoIssues() throws {
        try write(string: 1, fret: 0)
        XCTAssertTrue(try library.reconcile().isEmpty)
    }

    func testReconcileReportsARowWhoseAudioHasGone() throws {
        try write(string: 1, fret: 0)
        try FileManager.default.removeItem(at: try audioURL(string: 1, fret: 0))
        XCTAssertEqual(try library.reconcile(), [.missingAudio(string: 1, fret: 0)])
    }

    func testReconcileReportsAudioNoRowMentions() throws {
        try write(string: 1, fret: 0)
        let stray = directory.appendingPathComponent("s4-f09-m073.wav")
        try Data("not really audio".utf8).write(to: stray)
        XCTAssertEqual(try library.reconcile(), [.untrackedAudio(filename: "s4-f09-m073.wav")])
    }

    /// The ordering guarantee, exercised rather than asserted in a comment: if
    /// the manifest write fails after the audio is in place, what survives is
    /// an untracked audio file — the recoverable direction — never a row
    /// claiming a sample that is not there.
    func testAFailedManifestWriteLeavesUntrackedAudioNotAPhantomRow() throws {
        // A directory where the manifest belongs makes writing it fail.
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("manifest.json"),
            withIntermediateDirectories: false
        )
        XCTAssertThrowsError(try library.write(take: take(), string: 1, fret: 0, frequency: 110, cents: 0))

        XCTAssertTrue(FileManager.default.fileExists(atPath: try audioURL(string: 1, fret: 0).path))
        XCTAssertEqual(try library.entries().count, 0, "no row may claim a sample the manifest never recorded")
        XCTAssertEqual(try library.reconcile(), [.untrackedAudio(filename: "s1-f00-m045.wav")])
    }

    // MARK: - Peak consistency

    func testAPeakFarFromTheSessionMedianIsFlaggedButStillAccepted() throws {
        for string in 0..<3 {
            let entry = try write(string: string, fret: 0, peak: 0.5)
            XCTAssertFalse(entry.peakFlagged, "a consistent take must not be flagged")
        }
        let outlier = try write(string: 3, fret: 0, peak: 0.1)
        XCTAssertTrue(outlier.peakFlagged)
        XCTAssertEqual(try library.entries().count, 4, "a flagged take is still recorded")
    }

    func testTheFirstTakeOfASessionIsNeverFlagged() throws {
        XCTAssertFalse(try write(string: 0, fret: 0, peak: 0.05).peakFlagged)
    }
}
#endif
