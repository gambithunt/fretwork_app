import SwiftUI
import XCTest
@testable import Fretwork

/// The window minimums in `FretlightApp` are documented as measured rather than
/// guessed, and `CLAUDE.md` workflow 4 describes how: render the view through
/// an off-screen `NSHostingView` and read its `fittingSize`.
///
/// Until now that measurement lived only in a source comment, so nothing failed
/// if the screen grew past the number it justified. Workstream 005 adds a
/// sidebar and changes the screen's composition, which is exactly when a stale
/// minimum starts clipping something — so the measurement becomes a test.
@MainActor
final class WindowSizeTests: XCTestCase {
    /// What `FretlightApp`'s `WindowGroup` declares.
    private let declared = CGSize(width: 950, height: 800)

    func testTheDeclaredMinimumStillContainsTheListeningScreen() {
        let view = ListenScreen(state: AppState())
        let fitting = NSHostingView(rootView: view).fittingSize

        XCTAssertGreaterThanOrEqual(
            declared.width, fitting.width,
            "declared minWidth \(declared.width) is under the measured \(fitting.width) — re-derive it, do not just raise it"
        )
        XCTAssertGreaterThanOrEqual(
            declared.height, fitting.height,
            "declared minHeight \(declared.height) is under the measured \(fitting.height) — re-derive it, do not just raise it"
        )

        report("ListenScreen fittingSize = \(fitting.width) x \(fitting.height)")
    }

    /// **`NSHostingView` cannot measure a `NavigationSplitView` off-screen.**
    /// It reports 0 x 0, so asserting the declared minimum "contains" it passes
    /// no matter how wrong the number is — a vacuous test, which is worse than
    /// none. This pins that behaviour so nobody reintroduces the measurement
    /// believing it means something.
    func testTheSplitViewCannotBeMeasuredOffScreen() {
        let fitting = NSHostingView(rootView: AppShell(state: AppState())).fittingSize
        report("AppShell fittingSize = \(fitting.width) x \(fitting.height) (expected 0 x 0 — see test)")
        XCTAssertEqual(fitting.width, 0, "NavigationSplitView now measures off-screen; the shell's width can be measured directly instead of composed")
        XCTAssertEqual(fitting.height, 0)
    }

    /// So the shell's minimum is *composed* from parts that can each be
    /// measured or are declared: the sidebar's own floor plus what the widest
    /// detail screen needs. The listening screen is the widest by a long way —
    /// the module placeholders are checked against it below.
    func testTheDeclaredMinimumWidthCoversSidebarPlusDetail() {
        let detail = NSHostingView(rootView: ListenScreen(state: AppState())).fittingSize
        let required = AppShell.sidebarMinimumWidth + detail.width
        report("AppShell required width = \(AppShell.sidebarMinimumWidth) sidebar + \(detail.width) detail = \(required)")

        XCTAssertGreaterThanOrEqual(
            declared.width, required,
            "declared minWidth \(declared.width) is under the sidebar (\(AppShell.sidebarMinimumWidth)) plus the detail screen (\(detail.width))"
        )
    }

    /// Every module placeholder must also fit. A module whose copy is wider
    /// than the detail column would push the window minimum up, and it is
    /// cheaper to know that now than after ten real screens are built.
    func testEveryModulePlaceholderFitsTheDetailColumn() {
        for module in LearningModule.allCases {
            let fitting = NSHostingView(rootView: ModulePlaceholderScreen(module: module)).fittingSize
            XCTAssertLessThanOrEqual(
                fitting.width, declared.width,
                "\(module.id)'s placeholder is \(fitting.width)pt wide, past the window minimum"
            )
        }
    }

    private func report(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["FRETWORK_BASELINE_REPORT"] else { return }
        let data = (line + "\n").data(using: .utf8)!
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
