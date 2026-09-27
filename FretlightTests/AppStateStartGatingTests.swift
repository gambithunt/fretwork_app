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

    private func makeState(startResult: Bool) -> (AppState, FakeAudioController) {
        let fake = FakeAudioController()
        fake.starts = startResult
        let state = AppState(audio: fake, store: PracticeStateStore(storage: InMemoryPracticeStorage()))
        return (state, fake)
    }

    func testRetryThatStartsNothingLeavesTheErrorBannerIntact() {
        let (state, fake) = makeState(startResult: false)
        state.errorMessage = "Audio connection lost"
        state.isReconnecting = true

        state.retryAudio()

        XCTAssertEqual(fake.startCount, 1, "retryAudio must still ask the controller to start")
        XCTAssertEqual(state.errorMessage, "Audio connection lost",
                       "a start that issued nothing must not wipe the message explaining why")
        XCTAssertTrue(state.isReconnecting)
    }

    func testRetryThatStartsClearsTheErrorBanner() {
        let (state, fake) = makeState(startResult: true)
        state.errorMessage = "Audio connection lost"
        state.isReconnecting = true

        state.retryAudio()

        XCTAssertEqual(fake.startCount, 1)
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isReconnecting)
    }
}
