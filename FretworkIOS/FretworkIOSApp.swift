import SwiftUI

/// iOS entry point.
///
/// The production root is the Phase 3 smoke view until the Phase 4 shell lands.
/// The Phase 1 capture harness is kept reachable in DEBUG behind a launch
/// argument (`-FretworkPhase1Harness`) because it is the only no-mic synthetic
/// pipeline and carries the latency/CPU/thermal instrumentation Phase 7 will
/// need again. It is never the default, so an ordinary launch is inert and does
/// not open a real session until Start is tapped.
@main
struct FretworkIOSApp: App {
    private var showsPhase1Harness: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-FretworkPhase1Harness")
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if showsPhase1Harness {
                Phase1HarnessView()
            } else {
                IOSAudioControllerSmokeView()
            }
        }
    }
}
