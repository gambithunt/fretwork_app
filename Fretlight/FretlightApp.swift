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
                // render). minWidth is *composed*, because the window holds a
                // sidebar beside the screen: the listening screen measures
                // 727pt at its tightest and `AppShell.sidebarMinimumWidth` adds
                // 200, so 927 is the floor; 950 leaves headroom so real-world
                // font/Dynamic Type variance can't crowd anything.
                //
                // It was 1359 until the global settings — devices, monitor,
                // sensitivity, tuning, board orientation — moved out of this
                // screen's header and into the shell's toolbar. Seven controls
                // in one non-wrapping row were what made the window wide; the
                // window got 430pt narrower by putting them where every screen
                // can reach them anyway.
                // minHeight: the whole stack, including the fretboard's own
                // 260pt floor (see ListenScreen), measures 772pt, rounded up to
                // 800. Below this the fretboard is forced under its floor and
                // something clips.
                //
                // Composed rather than measured whole because `NSHostingView`
                // reports 0 x 0 for a `NavigationSplitView` off-screen — an
                // assertion against that number passes however wrong it is.
                // `WindowSizeTests` pins both the composition and the 0 x 0.
                //
                // The height was 700, justified by a 682pt measurement that had
                // since gone stale — the screen had grown to 772 and the
                // window would still let you drag it down to 700. The comment
                // was the only record of the measurement, so nothing failed
                // when the screen outgrew it. `WindowSizeTests` now re-measures
                // on every run; if it fails, re-derive these numbers rather
                // than raising them until it passes.
                .frame(minWidth: 950, minHeight: 800)
        }
        // `.automatic` (the default) keeps re-deriving the window's *ideal*
        // size from whatever's on screen, and the Listen screen's ideal size
        // and a module screen's `ScrollView` ideal size are not the same
        // number — so the very first navigation away from Listen nudged the
        // window a few points, before any manual resize had pinned it.
        // `.contentMinSize` makes the declared `minWidth`/`minHeight` above
        // the window's one fixed baseline instead, so switching screens can
        // no longer re-propose a size.
        .windowResizability(.contentMinSize)
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
