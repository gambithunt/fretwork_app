import SwiftUI
import UIKit

/// Pure decision: should the iPhone keep its screen awake right now?
///
/// iOS-only; the Mac never applies it. The screen stays awake only while the
/// iOS audio controller is actively `.listening` (which includes the moments a
/// sample is playing inside a listening run — the status does not leave
/// `.listening` during the playback gate), the player has left the setting on,
/// and the scene is foreground-active. Every other state — stopped, error,
/// interrupted, background, setting off — turns the idle timer back on.
enum IOSKeepScreenOnDecision {
    static func shouldKeepScreenOn(
        status: IOSAudioStatus?,
        settingEnabled: Bool,
        sceneActive: Bool
    ) -> Bool {
        guard settingEnabled, sceneActive else { return false }
        return status == .listening
    }
}

/// The single observer that applies `isIdleTimerDisabled`. Attached once at the
/// iOS root so the decision is driven from one place — status, setting and
/// scene phase — rather than scattered calls across screens.
private struct IOSKeepScreenOnModifier: ViewModifier {
    let state: AppState
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { apply() }
            .onChange(of: state.iosAudio?.status) { _, _ in apply() }
            .onChange(of: state.keepsScreenOnWhileListening) { _, _ in apply() }
            .onChange(of: scenePhase) { _, _ in apply() }
    }

    private func apply() {
        UIApplication.shared.isIdleTimerDisabled = IOSKeepScreenOnDecision.shouldKeepScreenOn(
            status: state.iosAudio?.status,
            settingEnabled: state.keepsScreenOnWhileListening,
            sceneActive: scenePhase == .active
        )
    }
}

extension View {
    func fretworkKeepsScreenOn(state: AppState) -> some View {
        modifier(IOSKeepScreenOnModifier(state: state))
    }
}
