import Sparkle
import SwiftUI

/// Mirrors Sparkle's `canCheckForUpdates` into observable state.
///
/// The property is KVO-compliant rather than `@Observable`, and it goes false
/// while a check is already in flight, so without this the menu item would stay
/// enabled and a second check would silently do nothing.
@MainActor
@Observable
final class UpdaterState {
    private(set) var canCheckForUpdates: Bool
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { updater, _ in
            // KVO fires on whichever thread mutated the property, so hop rather
            // than assume isolation — `assumeIsolated` would trap off-main.
            let value = updater.canCheckForUpdates
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = value
            }
        }
    }
}

/// The "Check for Updates…" item, for the app menu right under About.
struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    @State private var state: UpdaterState

    init(updater: SPUUpdater) {
        self.updater = updater
        _state = State(initialValue: UpdaterState(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!state.canCheckForUpdates)
    }
}
