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
        XCTAssertEqual(usage, "Fretwork listens to your guitar input to identify notes.")
    }

    func testHostedBundleHasNoSparkleKeys() {
        let forbiddenKeys = ["SUFeedURL", "SUPublicEDKey", "SUEnableInstallerLauncherService"]
        for key in forbiddenKeys {
            XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: key), "iOS bundle must not inherit Sparkle key \(key)")
        }
    }
}
