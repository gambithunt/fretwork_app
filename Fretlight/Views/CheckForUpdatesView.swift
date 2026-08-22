import Sparkle
import SwiftUI

/// The "Check for Updates…" item, for the app menu right under About.
struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        // `canCheckForUpdates` goes false while a check is already running.
        // Reading it here rather than observing it is deliberate: `body` is
        // main-actor isolated and so is the property, whereas bridging its KVO
        // notifications across to an @Observable model cannot be done without
        // capturing non-Sendable state in a @Sendable closure. A menu is
        // rebuilt each time it opens, which is exactly when the value matters.
        .disabled(!updater.canCheckForUpdates)
    }
}
