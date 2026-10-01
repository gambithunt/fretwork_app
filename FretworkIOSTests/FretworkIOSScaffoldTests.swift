import XCTest
@testable import Fretwork

@MainActor
final class FretworkIOSScaffoldTests: XCTestCase {
    func testScaffoldModuleIsLinkedAndPhase0IdentifierRemainsCovered() {
        XCTAssertEqual(IOSScaffoldPhase.phase0Identifier, "workstream-009-phase-0")
        XCTAssertEqual(IOSScaffoldPhase.phase1Identifier, "workstream-009-phase-1-simulator-first")
    }

    func testHostedAppMinimumOSIs26() {
        let minimumOS = Bundle.main.object(forInfoDictionaryKey: "MinimumOSVersion") as? String
        XCTAssertEqual(minimumOS, "26.0")
    }

    func testHostedBundleHasIOSIdentityAndPrivacyString() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "org.fretwork.app.ios")
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        XCTAssertEqual(
            usage,
            "Fretwork listens to your guitar to show the notes you play. Audio is analysed on this device and is never recorded or sent anywhere."
        )
    }

    func testHostedBundleDeclaresNonExemptEncryption() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool, false)
    }

    func testHostedBundleHasNoSparkleKeys() {
        let forbiddenKeys = ["SUFeedURL", "SUPublicEDKey", "SUEnableInstallerLauncherService"]
        for key in forbiddenKeys {
            XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: key), "iOS bundle must not inherit Sparkle key \(key)")
        }
    }

    func testHostedBundleShipsPrivacyManifestDeclaringNoCollection() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "iOS bundle must ship PrivacyInfo.xcprivacy"
        )
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty ?? false)
        XCTAssertTrue((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty ?? false)

        let accessed = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        let reasons = Dictionary(uniqueKeysWithValues: (accessed ?? []).compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        })
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategorySystemBootTime"], ["35F9.1"])
    }
}
