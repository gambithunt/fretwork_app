import XCTest
@testable import Fretwork

/// The shared, platform-neutral surface `AppState` exposes to a controller.
///
/// Everything here runs against `FakeAudioController` and an in-memory store,
/// so it needs no device and can run unchanged on iOS later. It never uses the
/// Mac `AppState()` convenience init, which constructs `MacAudioController` and
/// enumerates devices in its initialiser — the documented ~30s cost in the test
/// host when the microphone grant is missing.
@MainActor
final class AppStateSharedSurfaceTests: XCTestCase {

    private func makeState() -> (AppState, FakeAudioController, PracticeStateStore) {
        let store = PracticeStateStore(storage: InMemoryPracticeStorage())
        let fake = FakeAudioController()
        let state = AppState(audio: fake, store: store)
        return (state, fake, store)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Sample playback wiring

    /// Opening a module must ask the controller for the library. The absence of
    /// this was invisible: every tap called `playSample` while nothing had ever
    /// decoded the library, so nothing sounded and nothing said why.
    func testOpeningAModuleAsksForTheSampleLibrary() {
        let (state, fake, _) = makeState()
        XCTAssertEqual(fake.prepareSamplePlaybackCount, 0, "the 85 MB library is decoded lazily")

        state.selectedScreen = .module(.notes)

        XCTAssertEqual(fake.prepareSamplePlaybackCount, 1)
    }

    func testTheListeningScreenDoesNotAskForTheLibrary() {
        let (state, fake, _) = makeState()
        state.selectedScreen = .listen
        XCTAssertEqual(fake.prepareSamplePlaybackCount, 0)
    }

    func testPlaybackReadinessIsMirroredFromTheController() async {
        let (state, fake, _) = makeState()
        fake.isSamplePlaybackReady = true

        state.selectedScreen = .module(.notes)
        await waitUntil { state.isSamplePlaybackReady }

        XCTAssertTrue(state.isSamplePlaybackReady)
        XCTAssertNil(state.samplePlaybackError)
    }

    func testReadinessIsRefreshedWhenAModuleAsks() {
        let (state, fake, _) = makeState()
        state.selectedScreen = .module(.notes)
        XCTAssertFalse(state.isSamplePlaybackReady)

        fake.isSamplePlaybackReady = true
        state.refreshSamplePlaybackReadiness()
        XCTAssertTrue(state.isSamplePlaybackReady, "a refresh must re-read the controller after a graph rebuild")
    }

    func testAPreparationFailureIsSurfacedAndRetryable() async {
        let (state, fake, _) = makeState()
        fake.prepareError = "library missing"

        state.selectedScreen = .module(.notes)
        await waitUntil { state.samplePlaybackError != nil }

        XCTAssertEqual(state.samplePlaybackError, "library missing")
        XCTAssertEqual(fake.prepareSamplePlaybackCount, 1)

        // The failure must not latch `hasRequestedSamplePlayback`, or the next
        // module open would silently skip the decode for the whole session.
        state.refreshSamplePlaybackReadiness()
        XCTAssertEqual(fake.prepareSamplePlaybackCount, 2)
    }

    /// The module's `play:` closure must reach the controller with the tapped
    /// position and the state's current tuning.
    func testModulePlayClosureReachesTheControllerWithThePosition() {
        let (state, fake, _) = makeState()
        state.tuning = Tunings.dropD
        state.selectedScreen = .module(.notes)

        let model = state.makeNotesModuleModel()
        model.tapCell(string: 1, fret: 5)

        XCTAssertEqual(fake.played.count, 1)
        XCTAssertEqual(fake.played.first?.string, 1)
        XCTAssertEqual(fake.played.first?.fret, 5)
        XCTAssertEqual(fake.played.first?.tuning, Tunings.dropD)
    }

    // MARK: - Detection gating

    /// Gating follows the screen and the mode, and it only flips the worker
    /// flag — it must never rebuild the graph.
    func testDetectionGatingFollowsScreenAndModeWithoutStartingAudio() {
        let (state, fake, _) = makeState()

        state.selectedScreen = .listen
        state.detectionMode = .chords
        XCTAssertTrue(fake.chordDetectionEnabled, "Listen in chord mode must detect")

        state.selectedScreen = .module(.notes)
        XCTAssertFalse(fake.chordDetectionEnabled, "a module shows no live readout")

        state.selectedScreen = .listen
        XCTAssertTrue(fake.chordDetectionEnabled, "returning to Listen brings detection back")

        state.detectionMode = .notes
        XCTAssertFalse(fake.chordDetectionEnabled, "note mode never uses the chord detector")

        XCTAssertEqual(fake.startCount, 0, "gating must never start or rebuild the audio graph")
    }

    // MARK: - Sensitivity

    func testSensitivityWriteReachesControllerAndPersists() {
        let (state, fake, store) = makeState()

        state.sensitivity = 0.3

        XCTAssertEqual(fake.sensitivity, 0.3)
        XCTAssertEqual(store.state.settings.sensitivity, 0.3)
    }

    /// `sensitivity` has a `didSet`, and the restore in `init` must reach the
    /// controller rather than only updating the property. Historically the
    /// explicit `applySensitivity()` was the only path, because observers were
    /// not expected to fire during `init`; under `@Observable` the property is
    /// computed and its `didSet` *does* fire here, so the explicit call is
    /// idempotent. Whichever path applies it, the controller must end up with
    /// the restored value — otherwise the slider shows 0.7 while the detector
    /// runs at its default all session.
    func testRestoredSensitivityIsAppliedOnInitDespiteTheDidSetGotcha() {
        let store = PracticeStateStore(storage: InMemoryPracticeStorage())
        store.update { $0.settings.sensitivity = 0.7 }
        let fake = FakeAudioController()

        let state = AppState(audio: fake, store: store)

        XCTAssertEqual(state.sensitivity, 0.7)
        XCTAssertEqual(fake.sensitivity, 0.7, "the restored value must be pushed to the controller during init")
        XCTAssertTrue(fake.sensitivityValues.allSatisfy { $0 == 0.7 },
                      "no path may apply a stale default over the restored value")
    }

    // MARK: - Events

    func testNoteUpdateDrivesTheDisplayAndPositions() {
        let (state, fake, _) = makeState()
        let note = MappedNote(name: "A", octave: 4, midiNote: 69, cents: 1)
        var update = PitchDisplayState()
        update.frequency = 440
        update.note = note
        update.bufferSize = 256

        fake.emit(.noteUpdate(update))

        XCTAssertEqual(state.display.note?.midiNote, 69)
        XCTAssertEqual(state.display.frequency, 440)
        XCTAssertFalse(state.fretPositions.isEmpty, "a resolved note must mark candidate positions")
    }

    func testChordUpdateDrivesTheChordDisplayAndHistory() {
        let (state, fake, _) = makeState()
        let match = ChordMatch(root: "C", quality: .major, confidence: 0.9)
        var update = ChordDisplayState()
        update.chord = match
        update.level = 0.4

        fake.emit(.chordUpdate(update))

        XCTAssertEqual(state.chordDisplay.chord, match)
        XCTAssertEqual(state.chordHistory.last?.match, match)
    }

    func testErrorEventSetsTheMessageAndClearsReconnecting() {
        let (state, fake, _) = makeState()
        state.isReconnecting = true

        fake.emit(.error("Lost the device"))

        XCTAssertEqual(state.errorMessage, "Lost the device")
        XCTAssertFalse(state.isReconnecting)
    }

    func testRecoveredEventClearsTheErrorAndMarksAudioStarted() {
        let (state, fake, _) = makeState()
        state.errorMessage = "Lost the device"
        state.isReconnecting = true

        fake.emit(.recovered)

        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isReconnecting)
        XCTAssertTrue(state.hasStartedAudio)
    }

    func testReconnectingEventSetsTheFlag() {
        let (state, fake, _) = makeState()

        fake.emit(.reconnecting)

        XCTAssertTrue(state.isReconnecting)
    }
}
