import XCTest
@testable import Fretwork

/// The Retry path must not blank the error banner when there is nothing to
/// start.
///
/// `AppState.start()` used to clear `errorMessage`/`isReconnecting` after its
/// own device guard, but once device selection moved behind the audio seam
/// `AppState` could no longer see that guard: a `start()` that issued nothing
/// (no device selected) still cleared the flags, so a player staring at "Audio
/// connection lost" who hit Retry lost the explanation and got a silent screen.
/// The seam's `start()` now reports whether it started anything.
@MainActor
final class AppStateStartGatingTests: XCTestCase {

    func testRetryThatStartsNothingLeavesTheErrorBannerIntact() {
        let fake = GatingStubAudioController()
        fake.starts = false
        let state = AppState(audio: fake, store: PracticeStateStore(storage: InMemoryPracticeStorage()))
        state.errorMessage = "Audio connection lost"
        state.isReconnecting = true

        state.retryAudio()

        XCTAssertEqual(fake.startCount, 1, "retryAudio must still ask the controller to start")
        XCTAssertEqual(state.errorMessage, "Audio connection lost",
                       "a start that issued nothing must not wipe the message explaining why")
        XCTAssertTrue(state.isReconnecting)
    }

    func testRetryThatStartsClearsTheErrorBanner() {
        let fake = GatingStubAudioController()
        fake.starts = true
        let state = AppState(audio: fake, store: PracticeStateStore(storage: InMemoryPracticeStorage()))
        state.errorMessage = "Audio connection lost"
        state.isReconnecting = true

        state.retryAudio()

        XCTAssertEqual(fake.startCount, 1)
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isReconnecting)
    }
}

/// In-memory `PracticeStorage`: these tests must never touch the real defaults
/// domain, and using `AppState()` would enumerate audio devices in its
/// initialiser (the documented ~30s HAL cost in the test host).
private final class InMemoryPracticeStorage: PracticeStorage {
    private var data: Data?

    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}

/// A controllable `AudioControlling` whose `start()` result the test decides,
/// so the gating behaviour can be asserted without a device.
@MainActor
private final class GatingStubAudioController: AudioControlling {
    var onEvent: (@MainActor @Sendable (AudioControllerEvent) -> Void)?
    var starts = true
    private(set) var startCount = 0

    @discardableResult
    func start() -> Bool {
        startCount += 1
        return starts
    }

    func stop() {}
    func setChordDetectionEnabled(_ enabled: Bool) {}
    func setSensitivity(_ value: Double) {}
    func prepareSamplePlayback(completion: (@Sendable (String?) -> Void)?) {}
    var isSamplePlaybackReady: Bool { false }
    var isSampleLibraryLoaded: Bool { false }
    func playSample(string: Int, fret: Int, tuning: Tuning) {}
}
