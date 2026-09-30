import XCTest
@testable import Fretwork

/// Controller-level gate tests: a detection delivered during playback reaches
/// no downstream consumer, the readout clears when playback starts, and the
/// first post-gate updates are dropped so a pre-reset reading cannot leak.
@MainActor
final class IOSPlaybackGateTests: XCTestCase {

    /// Monotonic time source stepped by the test, satisfying the controller's
    /// `now` seam without a real clock.
    private final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: TimeInterval = 0
        var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return _now }
        func advance(_ seconds: TimeInterval) { lock.lock(); _now += seconds; lock.unlock() }
    }

    private func makeController(now: @escaping @Sendable () -> TimeInterval)
        -> (IOSAudioController, FakeIOSForegroundObserver) {
        let session = FakeIOSAudioSession()
        let foreground = FakeIOSForegroundObserver()
        let builder = FakeIOSAudioGraphBuilder()
        let controller = IOSAudioController(
            session: session,
            foreground: foreground,
            graphBuilder: builder,
            now: now
        )
        return (controller, foreground)
    }

    private func loadLibrary(_ controller: IOSAudioController) async {
        let loaded = expectation(description: "library decoded")
        controller.prepareSamplePlayback { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 60)
    }

    func testGatedDetectionReachesNothingAndReadoutClears() async throws {
        let clock = FakeClock()
        let (controller, foreground) = makeController(now: { clock.now })
        foreground.fire(true)
        XCTAssertTrue(controller.start())
        await loadLibrary(controller)
        await controller.settleGraphWork()
        XCTAssertEqual(controller.status, .listening)

        let appState = AppState(audio: controller, store: PracticeStateStore())
        let note = MappedNote(name: "E", octave: 2, midiNote: 40, cents: 0)
        let display = PitchDisplayState(level: 0.1, note: note)

        // A detection before playback lands normally.
        XCTAssertTrue(controller.deliverWorkerNoteForTesting(display))
        XCTAssertEqual(appState.display.note?.midiNote, 40)

        // Playback starts: the gate closes and the readout clears.
        controller.playSample(string: 0, fret: 0, tuning: Tunings.standard)
        XCTAssertNil(appState.display.note, "readout clears when playback starts")

        // A detection during the gate is dropped: no readout, no history.
        XCTAssertFalse(controller.deliverWorkerNoteForTesting(display))
        XCTAssertNil(appState.display.note)
        XCTAssertFalse(controller.deliverWorkerChordForTesting(ChordDisplayState(chord: nil, level: 0.1)))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(appState.noteHistory.isEmpty, "no history append during the gate")
        XCTAssertTrue(appState.chordHistory.isEmpty)

        // Advance past the low-E take's 4 s + 150 ms tail. The first two
        // post-gate deliveries are dropped (stale pre-reset frames); the third
        // is fresh and reaches AppState.
        clock.advance(4.2)
        XCTAssertFalse(controller.deliverWorkerNoteForTesting(display), "stale pre-reset frame")
        XCTAssertFalse(controller.deliverWorkerNoteForTesting(display), "reset margin frame")
        XCTAssertTrue(controller.deliverWorkerNoteForTesting(display), "fresh post-gate detection")
        XCTAssertEqual(appState.display.note?.midiNote, 40)
    }

    func testLiftFlagFlipsWithoutWorkerTraffic() async throws {
        let clock = FakeClock()
        let (controller, foreground) = makeController(now: { clock.now })
        foreground.fire(true)
        XCTAssertTrue(controller.start())
        await loadLibrary(controller)
        await controller.settleGraphWork()
        XCTAssertEqual(controller.status, .listening)

        // 17th fret high e is a 3.071 s take; the gate runs to 3.071 + 0.150 s.
        controller.playSample(string: 5, fret: 17, tuning: Tunings.standard)
        XCTAssertTrue(controller.isSuppressingForPlayback)

        // Move the injected clock past end + tail, then wait for the scheduled
        // lift check — with NO worker update driving the transition.
        clock.advance(3.3)
        try await Task.sleep(for: .seconds(3.4))
        XCTAssertFalse(controller.isSuppressingForPlayback, "the lift check flips the flag at gateEnd even without worker traffic")
    }
}
