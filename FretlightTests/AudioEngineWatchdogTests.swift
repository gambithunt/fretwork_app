import AVFoundation
import XCTest
@testable import Fretwork

/// Workstream 006 follow-up: a device that never answers must not take the app
/// down with it.
///
/// Measured before this fix: with an interface unplugged mid-session,
/// `AVAudioEngine.inputNode` sat in `AudioDeviceCreateIOProcID` waiting on a
/// `mach_msg` reply from coreaudiod for over 90 seconds and did not return.
/// Because graph building shared a queue with the rest of the control surface,
/// every later action queued behind it silently — the window stayed responsive,
/// so it looked like the app was fine and the audio had merely gone quiet.
final class AudioEngineWatchdogTests: XCTestCase {
    /// A device id that cannot resolve, so the build fails rather than binding
    /// anything real. The point is the *reporting*, not the failure.
    private let unusable: AudioDeviceID = 0xFFFF_FFFE

    /// **Opt-in**, via `TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1`, for a
    /// reason worth stating: these tests deliberately drive the pathological
    /// Core Audio path — a bind that never returns. Measured, that does not
    /// stay inside this process. Running them in the default suite left the
    /// HAL unwilling to answer for the *other* test processes XCTest runs in
    /// parallel, and the whole run stalled after 411 passing tests with no
    /// failure and no message. A test that deliberately wedges a device cannot
    /// share a machine with tests that need one.
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FRETWORK_AUDIO_DEVICE_TESTS"] == "1",
            "set TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1 to run the device-binding tests"
        )
    }

    /// The control surface must stay usable while a build is in flight, which
    /// is the whole reason the queues are separate. If these ran on the same
    /// queue as the build, a stuck build would make every one of them hang.
    func testControlOperationsDoNotQueueBehindAGraphBuild() {
        let engine = AudioEngine()
        engine.start(inputDeviceID: unusable, outputDeviceID: unusable, monitorVolume: 0.5)

        let done = expectation(description: "control operations complete")
        done.expectedFulfillmentCount = 4
        for value in [Float(0.1), 0.2, 0.3, 0.4] {
            DispatchQueue.global().async {
                engine.setMonitorVolume(value)
                engine.playSample(string: 0, fret: 0)
                engine.stopSamplePlayback()
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        engine.stop()
    }

    /// A build that cannot succeed must report, not go quiet.
    func testAFailedBuildReportsAnError() {
        let engine = AudioEngine()
        let reported = expectation(description: "error")
        reported.assertForOverFulfill = false
        engine.onError = { _ in reported.fulfill() }

        engine.start(inputDeviceID: unusable, outputDeviceID: unusable, monitorVolume: 0.5)
        // Measured at ~15s, which is the watchdog's own threshold rather than a
        // fast failure: binding a device id that cannot resolve *also* hangs
        // inside Core Audio rather than returning an error. That is worth
        // knowing — it means the watchdog is not a backstop for an exotic case,
        // it is the only thing that reports at all here.
        wait(for: [reported], timeout: 25)
        engine.stop()
    }

    /// The claim the queue split was made for: a device that hangs must not
    /// trap the player there. Selecting a different one has to recover, which
    /// is only possible because the control surface is no longer queued behind
    /// the stuck build.
    ///
    /// Skips rather than fails if the machine has no second device to move to —
    /// that is a fact about the machine, not a defect.
    func testSelectingAnotherDeviceRecoversFromAHungOne() throws {
        let inputs = AudioDeviceEnumerator.inputDevices()
        let outputs = AudioDeviceEnumerator.outputDevices()
        try XCTSkipIf(inputs.isEmpty || outputs.isEmpty, "no audio devices on this machine")

        let engine = AudioEngine()
        // Start on a device that cannot answer.
        engine.start(inputDeviceID: unusable, outputDeviceID: unusable, monitorVolume: 0.4)

        // Now do what a player would: pick real hardware instead. Prefer an
        // output on the same physical box as the input.
        let input = inputs[0]
        let output = outputs.first { $0.name == input.name } ?? outputs[0]

        let recovered = expectation(description: "recovered")
        recovered.assertForOverFulfill = false
        engine.onRecovered = { recovered.fulfill() }
        engine.start(inputDeviceID: input.id, outputDeviceID: output.id, monitorVolume: 0.4)

        wait(for: [recovered], timeout: 30)
        engine.stop()
    }

    /// Stopping an engine whose build never completed must not deadlock.
    func testStopAfterAFailedBuildReturnsPromptly() {
        let engine = AudioEngine()
        engine.start(inputDeviceID: unusable, outputDeviceID: unusable, monitorVolume: 0.5)

        let stopped = expectation(description: "stopped")
        DispatchQueue.global().async {
            engine.stop()
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 10)
    }
}
