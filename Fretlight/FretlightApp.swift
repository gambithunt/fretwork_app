import SwiftUI

@main
struct FretworkApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                // Both measured, not guessed (via an off-screen NSHostingView
                // render). minWidth: the header's own natural width — title,
                // input/output pickers, rescan, monitor, sensitivity, all laid
                // out in one row with no wrapping — is 980pt; 1180 leaves
                // ~200pt of headroom so real-world font/Dynamic Type variance
                // can't bring anything close to crowding. minHeight: the rest
                // of the stack (header/tuner/input-level/telemetry) renders at
                // 385pt including its own padding, plus one more 14pt
                // inter-item gap, plus the fretboard's own 260pt floor (see
                // ContentView) — 659pt, rounded up. Below this the fretboard
                // would be forced under its floor and something would clip.
                .frame(minWidth: 1_180, minHeight: 680)
        }
    }
}
