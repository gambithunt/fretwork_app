#if DEBUG
import AppKit
import SwiftUI
import XCTest
@testable import Fretwork

@MainActor
final class SampleCaptureModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fretwork-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func model() -> SampleCaptureModel {
        SampleCaptureModel(directory: directory)
    }

    /// A clean take of whatever note actually lives at `position`.
    private func take(for position: FretPosition, amplitude: Float = 0.5, rate: Double = 48_000) -> SampleRecorder.Take {
        let midi = Tunings.standard.openMIDINotes[position.string] + position.fret
        return take(frequency: 440 * pow(2, Double(midi - 69) / 12), amplitude: amplitude, rate: rate)
    }

    private func take(frequency: Double, amplitude: Float = 0.5, rate: Double = 48_000) -> SampleRecorder.Take {
        let samples = (0..<Int(rate)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
        return SampleRecorder.Take(samples: samples, sampleRate: rate, peak: samples.reduce(0) { max($0, abs($1)) })
    }

    // MARK: - Session flow

    func testAFreshSessionStartsAtTheFirstMissingPosition() {
        XCTAssertEqual(model().currentPosition, FretPosition(string: 0, fret: 0))
    }

    func testAnAcceptedTakeIsWrittenAndTheSessionAdvances() throws {
        let model = model()
        let start = try XCTUnwrap(model.currentPosition)
        model.handle(take: take(for: start))

        guard case .accepted = try XCTUnwrap(model.lastVerdict) else {
            return XCTFail("expected accepted, got \(String(describing: model.lastVerdict))")
        }
        XCTAssertEqual(model.recordedCount, 1)
        XCTAssertEqual(model.remainingCount, 137)
        XCTAssertEqual(model.currentPosition, FretPosition(string: 0, fret: 1))
        XCTAssertEqual(model.statuses[start], .recorded)
        XCTAssertNil(model.lastError)
    }

    func testARejectedTakeNeitherWritesNorAdvances() throws {
        let model = model()
        let start = try XCTUnwrap(model.currentPosition)
        // The note two frets up: right neighbourhood, wrong pitch.
        model.handle(take: take(for: FretPosition(string: 0, fret: 2)))

        guard case .wrongPitch = try XCTUnwrap(model.lastVerdict) else {
            return XCTFail("expected wrongPitch, got \(String(describing: model.lastVerdict))")
        }
        XCTAssertEqual(model.currentPosition, start, "a rejected take must not move the session on")
        XCTAssertEqual(model.recordedCount, 0)
        XCTAssertEqual(model.statuses[start], .missing)
    }

    func testEachRejectionReasonIsDistinguishable() throws {
        let model = model()
        let start = try XCTUnwrap(model.currentPosition)

        model.handle(take: take(for: start, amplitude: 0.005))
        XCTAssertEqual(model.lastVerdict, .tooQuiet)

        var generator = SystemRandomNumberGenerator()
        let noise = (0..<48_000).map { _ in Float.random(in: -0.5...0.5, using: &generator) }
        model.handle(take: SampleRecorder.Take(samples: noise, sampleRate: 48_000, peak: 0.5))
        XCTAssertEqual(model.lastVerdict, .noStablePitch)
    }

    func testAResumedSessionStartsAtTheFirstGap() throws {
        let first = model()
        let start = try XCTUnwrap(first.currentPosition)
        first.handle(take: take(for: start))

        let resumed = model()
        XCTAssertEqual(resumed.currentPosition, FretPosition(string: 0, fret: 1))
        XCTAssertEqual(resumed.recordedCount, 1)
        XCTAssertEqual(resumed.remainingCount, 137)
    }

    func testJumpingMovesTheSessionAndTheNextTakeLandsThere() throws {
        let model = model()
        let target = FretPosition(string: 3, fret: 7)
        model.jump(to: target)
        XCTAssertEqual(model.currentPosition, target)
        XCTAssertNil(model.lastVerdict, "jumping clears the previous judgement")

        model.handle(take: take(for: target))
        XCTAssertEqual(model.statuses[target], .recorded)
        XCTAssertEqual(model.statuses[FretPosition(string: 0, fret: 0)], .missing)
    }

    /// Advancing continues from where the operator is, rather than snapping
    /// back to the first gap on the neck.
    func testAdvancingContinuesFromTheCurrentPositionNotTheNut() throws {
        let model = model()
        let target = FretPosition(string: 3, fret: 7)
        model.jump(to: target)
        model.handle(take: take(for: target))
        XCTAssertEqual(model.currentPosition, FretPosition(string: 3, fret: 8))
    }

    func testRetakingReplacesOnePositionAndLeavesTheRestAlone() throws {
        let model = model()
        let first = FretPosition(string: 0, fret: 0)
        model.handle(take: take(for: first))
        model.handle(take: take(for: FretPosition(string: 0, fret: 1)))
        XCTAssertEqual(model.recordedCount, 2)

        model.jump(to: first)
        model.retakeCurrent()
        XCTAssertNil(model.lastVerdict)
        model.handle(take: take(for: first, amplitude: 0.4))

        XCTAssertEqual(model.recordedCount, 2, "a retake must not add a second entry")
        XCTAssertEqual(model.statuses[FretPosition(string: 0, fret: 1)], .recorded)
    }

    // MARK: - Stopping and resuming

    /// The folder has to outlive the process, or a resumed session has nothing
    /// to resume from. Uses its own defaults suite so the real domain is
    /// untouched.
    func testTheChosenFolderSurvivesARelaunch() throws {
        let suiteName = "fretwork.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(SampleCaptureDirectory.url(in: defaults), "nothing chosen yet")
        SampleCaptureDirectory.setURL(directory, in: defaults)
        XCTAssertEqual(SampleCaptureDirectory.url(in: defaults)?.path, directory.path)

        SampleCaptureDirectory.setURL(nil, in: defaults)
        XCTAssertNil(SampleCaptureDirectory.url(in: defaults))
    }

    /// The whole point of resuming: a session stopped partway comes back at
    /// the next thing to record, with the work already done still counted.
    func testASessionStoppedPartwayResumesWhereItLeftOff() throws {
        let first = model()
        for _ in 0..<4 {
            let position = try XCTUnwrap(first.currentPosition)
            first.handle(take: take(for: position))
        }
        XCTAssertEqual(first.recordedCount, 4)
        let stoppedAt = try XCTUnwrap(first.currentPosition)

        // A new model against the same folder is what a relaunch produces.
        let resumed = model()
        XCTAssertEqual(resumed.currentPosition, stoppedAt)
        XCTAssertEqual(resumed.recordedCount, 4)
        XCTAssertEqual(resumed.remainingCount, 134)
        XCTAssertEqual(resumed.statuses[FretPosition(string: 0, fret: 0)], .recorded)
    }

    /// A position skipped earlier is a gap, and resuming should send you back
    /// to fill it rather than leaving a hole 130 takes behind you.
    func testResumingReturnsToAGapLeftInTheMiddle() throws {
        let session = model()
        for fret in [0, 1, 3, 4] {
            let position = FretPosition(string: 0, fret: fret)
            session.jump(to: position)
            session.handle(take: take(for: position))
        }
        XCTAssertEqual(session.recordedCount, 4)

        let resumed = model()
        XCTAssertEqual(resumed.currentPosition, FretPosition(string: 0, fret: 2), "the skipped fret is the first gap")
    }

    func testAFullyRecordedLibraryResumesWithNothingLeftToDo() throws {
        let session = model()
        for position in SampleLibrary.expectedPositions {
            session.jump(to: position)
            session.handle(take: take(for: position))
        }
        XCTAssertEqual(session.recordedCount, SampleLibrary.expectedPositions.count)

        let resumed = model()
        XCTAssertNil(resumed.currentPosition, "nothing left to prompt for")
        XCTAssertEqual(resumed.remainingCount, 0)
    }

    // MARK: - Processing and status

    func testAcceptedTakesAreTrimmedAndNormalisedBeforeBeingWritten() throws {
        let model = model()
        let start = try XCTUnwrap(model.currentPosition)
        // A little leading silence, so trimming has something to remove — a
        // bare sine starts at its onset and would pass without being trimmed.
        // Kept under the attack-skip window, which is what a real take looks
        // like: `SampleRecorder` begins accumulating at onset, so it carries
        // at most one buffer of lead, not a third of a second.
        let played = take(for: start, amplitude: 0.2)
        let lead = [Float](repeating: 0, count: Int(played.sampleRate * 0.03))
        let quiet = SampleRecorder.Take(
            samples: lead + played.samples,
            sampleRate: played.sampleRate,
            peak: played.peak
        )
        model.handle(take: quiet)

        let entry = try XCTUnwrap(SampleLibrary(directory: directory).entries().first)
        // The entry records the level as *played*, which is the diagnostic —
        // the audio on disk is normalised, so its own peak carries no signal.
        XCTAssertEqual(entry.peak, quiet.peak, accuracy: 0.001)
        XCTAssertLessThan(entry.frameCount, quiet.samples.count, "the take should have been trimmed")
    }

    func testAPeakFarFromTheSessionMedianIsFlaggedSeparatelyFromRecorded() throws {
        let model = model()
        for fret in 0..<3 {
            model.jump(to: FretPosition(string: 0, fret: fret))
            model.handle(take: take(for: FretPosition(string: 0, fret: fret), amplitude: 0.5))
        }
        let outlier = FretPosition(string: 0, fret: 3)
        model.jump(to: outlier)
        model.handle(take: take(for: outlier, amplitude: 0.1))

        XCTAssertEqual(model.statuses[outlier], .flagged)
        XCTAssertEqual(model.statuses[FretPosition(string: 0, fret: 0)], .recorded)
        XCTAssertEqual(model.recordedCount, 4, "a flagged take still counts as recorded")
    }

    func testReconciliationIssuesAreSurfacedRatherThanRepaired() throws {
        let model = model()
        let start = try XCTUnwrap(model.currentPosition)
        model.handle(take: take(for: start))
        XCTAssertTrue(model.reconciliationIssues.isEmpty)

        let name = try XCTUnwrap(SampleLibrary.filename(string: start.string, fret: start.fret))
        try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        model.refresh()

        XCTAssertEqual(model.reconciliationIssues, [.missingAudio(string: start.string, fret: start.fret)])
        XCTAssertEqual(model.statuses[start], .recorded, "reconcile reports; it does not rewrite the manifest")
    }

    // MARK: - Layout

    /// `CLAUDE.md` requires window minimums to be measured rather than
    /// guessed. Doing it as a test rather than a throwaway harness means the
    /// number stays true as the view changes.
    func testDeclaredMinimumSizeContainsTheView() throws {
        let view = SampleCaptureView(
            model: model(),
            meter: CaptureLevelMeter(),
            arm: CaptureArmState(),
            onArm: {},
            onDisarm: {},
            onChooseDirectory: {}
        )
        let fitting = NSHostingView(rootView: view).fittingSize
        XCTAssertGreaterThanOrEqual(SampleCaptureView.minimumSize.width, fitting.width,
                                    "declared minimum width \(SampleCaptureView.minimumSize.width) is under the measured \(fitting.width)")
        XCTAssertGreaterThanOrEqual(SampleCaptureView.minimumSize.height, fitting.height,
                                    "declared minimum height \(SampleCaptureView.minimumSize.height) is under the measured \(fitting.height)")
    }
}
#endif
