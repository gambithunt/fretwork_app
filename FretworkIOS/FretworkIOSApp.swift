import SwiftUI

/// iOS entry point.
///
/// The production root is the workstream-009 shell (Phases 4–5): the iOS
/// navigation split by idiom, the Listen screen and the module placeholders.
/// The Phase 1/3/7 harnesses do not exist in Release at all: their sources are
/// wrapped in `#if DEBUG`, and the launch-argument dispatch below is too. A
/// release binary therefore carries no harness symbols and no launch-argument
/// surface — proved by `strings`/`nm` over the archived app, not by the switch.
@main
struct FretworkIOSApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
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
            #else
            IOSAppRootView()
            #endif
        }
    }

    #if DEBUG
    private var launchMode: LaunchMode {
        if CommandLine.arguments.contains("-FretworkPhase1Harness") { return .phase1Harness }
        if CommandLine.arguments.contains("-FretworkPhase3Smoke") { return .phase3Smoke }
        if CommandLine.arguments.contains("-FretworkBleedProbe") { return .bleedProbe }
        return .app
    }

    private enum LaunchMode {
        case phase1Harness
        case phase3Smoke
        case bleedProbe
        case app
    }
    #endif
}
