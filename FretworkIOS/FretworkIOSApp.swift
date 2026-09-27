import SwiftUI

/// Workstream 009 Phase 1 iOS harness entry point.
///
/// Launch remains inert: the root view constructs no audio session, requests no
/// permission and starts no engine. Synthetic or manual capture begins only from
/// the explicit Start button in the harness.
@main
struct FretworkIOSApp: App {
    var body: some Scene {
        WindowGroup {
            Phase1HarnessView()
        }
    }
}
