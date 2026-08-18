import SwiftUI

@main
struct FretworkApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                // minHeight is measured, not guessed: the header/tuner/input-level/
                // telemetry stack renders at 385pt (incl. its own padding) at this
                // width, plus one more 14pt inter-item gap, plus the fretboard's
                // own 260pt floor (see ContentView) — 659pt, rounded up for
                // headroom. Below this the fretboard would be forced under its
                // floor and something would clip.
                .frame(minWidth: 1_120, minHeight: 680)
        }
    }
}
