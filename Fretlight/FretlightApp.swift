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
                // out in one row with no wrapping — measures 1159pt at its
                // tightest; 1180 leaves headroom so real-world font/Dynamic
                // Type variance can't bring anything close to crowding.
                // minHeight: the whole stack, including the fretboard's own
                // 260pt floor (see ContentView), measures 772pt, rounded up to
                // 800. Below this the fretboard is forced under its floor and
                // something clips.
                //
                // The height was 700, justified by a 682pt measurement that had
                // since gone stale — the screen had grown to 772 and the
                // window would still let you drag it down to 700. The comment
                // was the only record of the measurement, so nothing failed
                // when the screen outgrew it. `WindowSizeTests` now re-measures
                // on every run; if it fails, re-derive these numbers rather
                // than raising them until it passes.
                .frame(minWidth: 1_180, minHeight: 800)
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
