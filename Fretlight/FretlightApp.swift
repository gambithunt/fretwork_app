import Sparkle
import SwiftUI

@main
struct FretworkApp: App {
    @State private var state = AppState()

    // Starting the updater here rather than lazily means the scheduled
    // background check (SUScheduledCheckInterval in Config/Info.plist) is
    // running from launch, not from the first time the menu is opened.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
#if DEBUG
                SampleCaptureCommand()
#endif
            }
        }

#if DEBUG
        // The sample-capture tool. Compiled out of Release entirely — it
        // writes files, assumes a cooperative operator, and exists only to
        // build the note library that ships as a resource.
        Window("Sample Capture", id: SampleCaptureCommand.windowID) {
            SampleCaptureHost(state: state)
                .frame(minWidth: SampleCaptureView.minimumSize.width,
                       minHeight: SampleCaptureView.minimumSize.height)
        }
#endif
    }
}

#if DEBUG
private struct SampleCaptureCommand: View {
    static let windowID = "sample-capture"

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Sample Capture…") { openWindow(id: Self.windowID) }
    }
}
#endif
