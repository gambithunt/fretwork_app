import SwiftUI

/// iOS entry point.
///
/// In DEBUG the workstream-009 prototype (direction C + M2) is the default
/// root, so an ordinary launch lands on the shell the owner will feel on a
/// real iPhone. The Phase 3 smoke view and the Phase 1 capture harness stay
/// reachable in DEBUG behind launch arguments — the harness because it is the
/// only no-mic synthetic pipeline, the smoke view because it is the one
/// surface that writes session/status figures to stderr for
/// `devicectl … --console`.
@main
struct FretworkIOSApp: App {
    private var launchMode: LaunchMode {
        #if DEBUG
        if CommandLine.arguments.contains("-FretworkPhase1Harness") { return .phase1Harness }
        if CommandLine.arguments.contains("-FretworkPhase3Smoke") { return .phase3Smoke }
        #endif
        return .prototype
    }

    var body: some Scene {
        WindowGroup {
            switch launchMode {
            case .phase1Harness:
                Phase1HarnessView()
            case .phase3Smoke:
                IOSAudioControllerSmokeView()
            case .prototype:
                IOSPrototypeRootView()
            }
        }
    }

    private enum LaunchMode {
        case phase1Harness
        case phase3Smoke
        case prototype
    }
}
