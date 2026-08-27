import CoreAudio
import XCTest
@testable import Fretwork

/// The app has to choose a device when it has no saved one — on first run, or
/// when the saved interface is gone.
///
/// It used to take the first enumerated device. Enumeration order is arbitrary,
/// and on a machine with a monitor attached the first output is often the
/// monitor's DisplayPort audio: measured here, binding that never returned, so
/// the app opened unable to play anything while the real speakers sat further
/// down the list. The system default is what a person means by "my speakers".
final class DefaultDeviceTests: XCTestCase {
    func testTheSystemDefaultsAreFoundAndAreRealDevices() throws {
        let outputs = AudioDeviceEnumerator.outputDevices()
        let inputs = AudioDeviceEnumerator.inputDevices()
        try XCTSkipIf(outputs.isEmpty || inputs.isEmpty, "no audio devices on this machine")

        let defaultOutput = AudioDeviceEnumerator.defaultDeviceID(scope: kAudioDevicePropertyScopeOutput)
        let defaultInput = AudioDeviceEnumerator.defaultDeviceID(scope: kAudioDevicePropertyScopeInput)
        XCTAssertNotNil(defaultOutput, "macOS always has a default output when any output exists")
        XCTAssertNotNil(defaultInput)

        // And they must be devices this app would actually offer, or the
        // fallback would select something the picker cannot show.
        XCTAssertTrue(outputs.contains { $0.id == defaultOutput }, "the default output is not in the output list")
        XCTAssertTrue(inputs.contains { $0.id == defaultInput }, "the default input is not in the input list")
    }

    /// The two scopes must not collapse to one device — that would silently
    /// force every machine onto the duplex path.
    func testTheInputAndOutputScopesAreQueriedSeparately() throws {
        let outputs = AudioDeviceEnumerator.outputDevices()
        try XCTSkipIf(outputs.isEmpty, "no audio devices on this machine")

        let output = AudioDeviceEnumerator.defaultDeviceID(scope: kAudioDevicePropertyScopeOutput)
        let input = AudioDeviceEnumerator.defaultDeviceID(scope: kAudioDevicePropertyScopeInput)
        // They may legitimately be the same physical device, but only when that
        // device really does serve both directions.
        if let output, let input, output == input {
            XCTAssertTrue(AudioDeviceEnumerator.isDuplexCapable(output),
                          "the same id was returned for both scopes but it is not duplex-capable")
        }
    }

    /// The whole point: a fresh state lands on the system default rather than
    /// on whatever happens to be first.
    @MainActor
    func testAFreshStateSelectsTheSystemDefaultOutput() throws {
        let outputs = AudioDeviceEnumerator.outputDevices()
        try XCTSkipIf(outputs.count < 2, "needs more than one output to be meaningful")
        let defaultOutput = try XCTUnwrap(AudioDeviceEnumerator.defaultDeviceID(scope: kAudioDevicePropertyScopeOutput))

        let state = AppState()
        // Only meaningful when nothing was restored; a saved selection rightly
        // wins over the default.
        if state.selectedOutputUIDForTesting == nil {
            XCTAssertEqual(state.selectedOutputDeviceID, defaultOutput,
                           "with no saved device the app should open on the system default")
        }
    }
}
