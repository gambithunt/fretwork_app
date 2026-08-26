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
    private let declared = CGSize(width: 1_180, height: 800)

    func testTheDeclaredMinimumStillContainsTheListeningScreen() {
        let view = ContentView(state: AppState())
        let fitting = NSHostingView(rootView: view).fittingSize

        XCTAssertGreaterThanOrEqual(
            declared.width, fitting.width,
            "declared minWidth \(declared.width) is under the measured \(fitting.width) — re-derive it, do not just raise it"
        )
        XCTAssertGreaterThanOrEqual(
            declared.height, fitting.height,
            "declared minHeight \(declared.height) is under the measured \(fitting.height) — re-derive it, do not just raise it"
        )

        // Reported so a later phase can attribute a change to the sidebar
        // rather than to drift somewhere else.
        if let path = ProcessInfo.processInfo.environment["FRETWORK_BASELINE_REPORT"] {
            try? "ListenScreen fittingSize = \(fitting.width) x \(fitting.height)\n"
                .write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
