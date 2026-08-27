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
    /// **Opt-in**, via `TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1`.
    ///
    /// It needs the real default device to build a graph, so under the full
    /// suite it contends with the other test processes XCTest runs in parallel —
    /// each of which also constructs an `AudioEngine`. Measured: 20s alone,
    /// past 45s in the suite. A hardware-dependent test in the default run is
    /// flaky by construction, and a flaky test teaches people to ignore red.
    ///
    /// The bug this was written for is still caught deterministically by
    /// `SamplePlaybackWiringTests`, which needs no device. What this adds is
    /// the last link — a player actually attached to a running graph — and that
    /// genuinely cannot be checked without hardware.
    func testANoteFromAModuleReachesARealPlayer() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FRETWORK_AUDIO_DEVICE_TESTS"] == "1",
            "set TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1 to run the hardware playback check"
        )
        let outputs = AudioDeviceEnumerator.outputDevices()
        let inputs = AudioDeviceEnumerator.inputDevices()
        try XCTSkipIf(outputs.isEmpty || inputs.isEmpty, "no audio devices on this machine")

        let state = AppState()

        // Choose the devices rather than inheriting whatever was last saved.
        // Measured on this machine: the saved interface was gone, so the app
        // fell back to the first enumerated output — a monitor's DisplayPort
        // audio, which never answers a bind. That is correct app behaviour (the
        // watchdog reports it), but it makes this test assert the machine's
        // device list rather than the playback path. Preferring an output whose
        // name matches an input picks the same physical box on both ends.
        let input = try XCTUnwrap(inputs.first)
        let output = outputs.first { $0.name == input.name } ?? outputs[0]
        state.selectInputDevice(input.id)
        state.selectOutputDevice(output.id)

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
