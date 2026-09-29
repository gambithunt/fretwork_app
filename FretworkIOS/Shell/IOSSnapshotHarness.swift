#if DEBUG
import UIKit

/// DEBUG-only deterministic screenshot harness.
///
/// Each `-IOSSnapshot*` launch argument drives one surface into a fixed state
/// so a `simctl io … screenshot` run can capture it without tapping. It skips
/// the real mic session because the iOS 26 simulator ignores the `simctl`
/// microphone grant and re-prompts, covering the chrome.
enum IOSSnapshotHarness {
    enum Scenario: String, CaseIterable {
        case listenPortrait = "-IOSSnapshotListenPortrait"
        case listenLandscape = "-IOSSnapshotListenLandscape"
        case chordsLandscape = "-IOSSnapshotChordsLandscape"
        case chordsDrawer = "-IOSSnapshotChordsDrawer"
        case settings = "-IOSSnapshotSettings"
        case permissionDenied = "-IOSSnapshotPermissionDenied"
    }

    static var scenario: Scenario? {
        Scenario.allCases.first { CommandLine.arguments.contains($0.rawValue) }
    }

    static var isActive: Bool { scenario != nil }

    /// Never open the real session during a capture: the permission prompt
    /// would sit over the surface being photographed.
    static var shouldSkipAudioSession: Bool { isActive }

    /// The status the pills and banner should render during the capture.
    static var forcedStatus: IOSAudioStatus? {
        switch scenario {
        case .permissionDenied: return .permissionDenied
        case .none: return nil
        default: return .listening
        }
    }

    static var forcesLandscape: Bool {
        switch scenario {
        case .listenLandscape, .chordsLandscape, .chordsDrawer: return true
        default: return false
        }
    }

    /// The navigation stack's initial path.
    static var initialPath: [AppScreen] {
        switch scenario {
        case .chordsLandscape, .chordsDrawer: return [.module(.chords)]
        default: return [.listen]
        }
    }

    static var showsSettingsSheet: Bool { scenario == .settings }
    static var showsChordsDrawer: Bool { scenario == .chordsDrawer }

    static func effectiveStatus(_ actual: IOSAudioStatus?) -> IOSAudioStatus? {
        guard isActive else { return actual }
        return forcedStatus
    }

    static func requestLandscapeIfNeeded() {
        guard forcesLandscape,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
    }
}
#endif
