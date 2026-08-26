import XCTest
@testable import Fretwork

/// Navigation must not disturb audio.
///
/// The risk is concrete and was live in this codebase: `AppState.start()` is a
/// full stop-and-rebuild of the render graph, and it used to be called from
/// `ListenScreen`'s `.task`. A screen's `.task` re-runs every time that screen
/// reappears, so once the app had more than one screen, every return to Listen
/// would have rebuilt the graph — re-prompting for the microphone, dropping the
/// direct-monitoring path, and feeding the restart path that `AudioEngine`
/// debounces and attempt-caps precisely because an uncapped restart loop was a
/// real bug.
///
/// `graphBuildCount` is the number that must not move.
@MainActor
final class AppShellNavigationTests: XCTestCase {
    func testChangingScreensNeverRebuildsTheGraph() {
        let state = AppState()
        let before = state.graphBuildCount

        for module in LearningModule.allCases {
            state.selectedScreen = .module(module)
        }
        state.selectedScreen = .listen
        for module in LearningModule.allCases.reversed() {
            state.selectedScreen = .module(module)
            state.selectedScreen = .listen
        }

        XCTAssertEqual(state.graphBuildCount, before,
                       "navigating rebuilt the audio graph \(state.graphBuildCount - before) time(s)")
    }

    func testTheSelectedScreenStartsOnListen() {
        XCTAssertEqual(AppState().selectedScreen, .listen)
    }

    /// The web app deliberately always opens on home rather than restoring the
    /// last module, and this app follows it. Pinned because "restore the last
    /// screen" is the kind of thing added later without noticing it was a
    /// decision.
    func testTheSelectedScreenIsNotPersisted() {
        let state = AppState()
        state.selectedScreen = .module(.pentatonic)

        // The persisted document has no field for it at all, which is the
        // strongest form of "not persisted": there is nowhere for it to go.
        let encoded = try? JSONEncoder().encode(PracticeState())
        let text = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertFalse(text.contains("Screen"), "the practice-state document gained a screen field: \(text)")
        XCTAssertFalse(text.contains("module\""), "the practice-state document gained an active-module field: \(text)")
        XCTAssertEqual(state.selectedScreen, .module(.pentatonic), "sanity: the selection itself still works in memory")
    }
}
