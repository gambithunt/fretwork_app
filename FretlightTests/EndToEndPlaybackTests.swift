import AVFoundation
import XCTest
@testable import Fretwork

/// End to end: `AppState` → `AudioEngine` → `SamplePlayer`, against the real
/// default output device.
///
/// The module tests inject a `play:` closure so they can run without an audio
/// graph, which is what let the first two modules ship silently mute — the
/// closure was called, the engine behind it was never initialised. This test
/// exists to close that gap: it asserts a note actually reaches a player.
@MainActor
final class EndToEndPlaybackTests: XCTestCase {
    /// Opening a module and playing a note must reach a real player attached to
    /// a running graph. Skips rather than fails when the machine has no usable
    /// audio device, since that is an environment fact and not a defect.
    func testANoteFromAModuleReachesARealPlayer() throws {
        let outputs = AudioDeviceEnumerator.outputDevices()
        let inputs = AudioDeviceEnumerator.inputDevices()
        try XCTSkipIf(outputs.isEmpty || inputs.isEmpty, "no audio devices on this machine")

        let state = AppState()
        // The app starts audio from `ContentView`'s `.task`; a unit test has no
        // view, so it has to do the same thing explicitly. Without this there is
        // no graph for a player to attach to and the test would be measuring
        // its own omission.
        state.start()
        state.selectedScreen = .module(.notes)

        let ready = expectation(description: "playback ready")
        Task { @MainActor in
            for _ in 0..<300 {
                state.refreshSamplePlaybackReadiness()
                if state.isSamplePlaybackReady { return ready.fulfill() }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        // The engine has to build a graph on a real device, which is slow on a
        // sick machine; the watchdog reports at 15s and this allows well past it.
        wait(for: [ready], timeout: 45)

        XCTAssertNil(state.samplePlaybackError)
        XCTAssertTrue(state.isSamplePlaybackReady,
                      "a module can play notes only once a player is attached to a running graph")
    }
}
