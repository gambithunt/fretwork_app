import SwiftUI

/// iOS entry point.
///
/// The production root is the workstream-009 shell (Phases 4–5): the iOS
/// navigation split by idiom, the Listen screen and the module placeholders.
/// The Phase 3 smoke view and the Phase 1 capture harness stay reachable only
/// in DEBUG behind launch arguments — the harness because it is the only
/// no-mic synthetic pipeline, the smoke view because it writes session/status
/// figures to stderr for `devicectl … --console`.
@main
struct FretworkIOSApp: App {
    private var launchMode: LaunchMode {
        #if DEBUG
        if CommandLine.arguments.contains("-FretworkPhase1Harness") { return .phase1Harness }
        if CommandLine.arguments.contains("-FretworkPhase3Smoke") { return .phase3Smoke }
        if CommandLine.arguments.contains("-FretworkBleedProbe") { return .bleedProbe }
        #endif
        return .app
    }

    var body: some Scene {
        WindowGroup {
            switch launchMode {
            case .phase1Harness:
                Phase1HarnessView()
            case .phase3Smoke:
                IOSAudioControllerSmokeView()
            case .bleedProbe:
                BleedProbeView()
            case .app:
                IOSAppRootView()
            }
        }
    }

    private enum LaunchMode {
        case phase1Harness
        case phase3Smoke
        case bleedProbe
        case app
    }
}
