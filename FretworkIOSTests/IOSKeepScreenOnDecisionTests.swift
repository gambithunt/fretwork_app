import XCTest
@testable import Fretwork

/// The keep-screen-on decision is a pure mapping of status × setting × scene,
/// so every combination is testable without a controller or `UIApplication`.
final class IOSKeepScreenOnDecisionTests: XCTestCase {

    func testKeepsScreenOnOnlyWhileListeningAndEnabledAndActive() {
        // The only true case: listening + on + foreground.
        XCTAssertTrue(IOSKeepScreenOnDecision.shouldKeepScreenOn(
            status: .listening, settingEnabled: true, sceneActive: true))

        // Setting off or backgrounded always disables, even while listening.
        XCTAssertFalse(IOSKeepScreenOnDecision.shouldKeepScreenOn(
            status: .listening, settingEnabled: false, sceneActive: true))
        XCTAssertFalse(IOSKeepScreenOnDecision.shouldKeepScreenOn(
            status: .listening, settingEnabled: true, sceneActive: false))

        // Every non-listening status disables, even with the setting on.
        for status: IOSAudioStatus? in [.idle, .starting, .interrupted, .permissionDenied, .failed("x"), nil] {
            XCTAssertFalse(IOSKeepScreenOnDecision.shouldKeepScreenOn(
                status: status, settingEnabled: true, sceneActive: true),
                "status \(String(describing: status)) must not keep the screen on")
        }
    }
}
