import CoreAudio
import XCTest
@testable import Fretwork

/// The device-resolution helpers were lifted out of `AppState` into
/// `MacAudioController` verbatim, so these test the extracted pure logic with
/// fabricated devices rather than standing up the HAL (which can take ~30s in
/// the test host when the microphone grant is missing).
final class MacAudioControllerTests: XCTestCase {

    private func device(id: AudioDeviceID, uid: String, name: String = "Device") -> AudioDevice {
        AudioDevice(id: id, name: name, uid: uid)
    }

    // MARK: - reresolve

    func testReresolveKeepsAnIDThatIsStillPresent() {
        let devices = [device(id: 7, uid: "seven"), device(id: 9, uid: "nine")]
        XCTAssertEqual(MacAudioController.reresolve(id: 9, uid: "seven", in: devices), 9)
    }

    func testReresolveFallsBackToTheStableUIDWhenTheIDChanged() {
        let devices = [device(id: 7, uid: "seven"), device(id: 42, uid: "nine")]
        XCTAssertEqual(MacAudioController.reresolve(id: 9, uid: "nine", in: devices), 42)
    }

    func testReresolveFallsBackToTheFirstDeviceWhenNeitherMatches() {
        let devices = [device(id: 7, uid: "seven"), device(id: 42, uid: "nine")]
        XCTAssertEqual(MacAudioController.reresolve(id: 99, uid: "gone", in: devices), 7)
    }

    func testReresolveIsNilWithNoDevices() {
        XCTAssertNil(MacAudioController.reresolve(id: 1, uid: "gone", in: []))
    }

    // MARK: - restoreSelection

    func testRestoreSelectionPrefersTheStableUID() {
        let devices = [device(id: 7, uid: "seven"), device(id: 42, uid: "nine")]
        XCTAssertEqual(MacAudioController.restoreSelection(uid: "nine", legacyID: 7, from: devices)?.id, 42)
    }

    func testRestoreSelectionFallsBackToTheLegacyIDWhenItStillResolves() {
        let devices = [device(id: 7, uid: "seven"), device(id: 42, uid: "nine")]
        XCTAssertEqual(MacAudioController.restoreSelection(uid: nil, legacyID: 42, from: devices)?.id, 42)
    }

    func testRestoreSelectionIgnoresALegacyIDThatIsGone() {
        let devices = [device(id: 7, uid: "seven")]
        XCTAssertNil(MacAudioController.restoreSelection(uid: nil, legacyID: 42, from: devices))
    }

    func testRestoreSelectionIsNilWhenNothingMatches() {
        let devices = [device(id: 7, uid: "seven")]
        XCTAssertNil(MacAudioController.restoreSelection(uid: "gone", legacyID: 42, from: devices))
    }

    func testRestoreSelectionIsNilWithNoDevices() {
        XCTAssertNil(MacAudioController.restoreSelection(uid: "nine", legacyID: 42, from: []))
    }
}
