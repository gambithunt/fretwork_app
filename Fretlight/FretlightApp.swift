import SwiftUI

@main
struct FretworkApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                // Both measured, not guessed (via an off-screen NSHostingView
                // render). minWidth: the header's own natural width — logo,
                // input/output pickers, rescan, monitor, sensitivity, all laid
                // out in one row with no wrapping — is 1105pt at its tightest;
                // 1180 leaves headroom so real-world font/Dynamic Type variance
                // can't bring anything close to crowding. minHeight: the whole
                // stack, including the fretboard's own 260pt floor (see
                // ContentView), fits in exactly 682pt — the dot-matrix input
                // meter is what raised it from the previous 659 — rounded up to
                // 700. Below this the fretboard would be forced under its floor
                // and something would clip.
                .frame(minWidth: 1_180, minHeight: 700)
        }
    }
}
