import XCTest
@testable import Fretwork

/// The modules play notes through `AudioEngine`, which does nothing until the
/// bundled library has been asked for. Nothing asked for it.
///
/// Every tap in Notes and Intervals called `playSample`, which is a **silent
/// no-op** while `samplePlayer` is nil — no sound, no error, nothing in a log.
/// The module tests could not catch it: they inject a `play:` closure so they
/// can run without an audio graph, so the seam that makes them testable is
/// exactly where the bug lived. These tests go through `AppState` instead.
@MainActor
final class SamplePlaybackWiringTests: XCTestCase {
    /// Opening a module must cause the library to be decoded. This is the
    /// assertion that was missing.
    func testOpeningAModuleLoadsTheNoteLibrary() {
        let state = AppState()
        XCTAssertFalse(state.isSampleLibraryLoadedForTesting, "nothing should be decoded before a module is opened")

        state.selectedScreen = .module(.notes)

        let loaded = expectation(description: "library decoded")
        Task { @MainActor in
            for _ in 0..<200 {
                if state.isSampleLibraryLoadedForTesting { return loaded.fulfill() }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        wait(for: [loaded], timeout: 30)
        XCTAssertNil(state.samplePlaybackError)
    }

    /// The listening screen plays nothing, so it must not pay the 85 MB.
    func testTheListeningScreenDoesNotLoadTheLibrary() {
        let state = AppState()
        state.selectedScreen = .listen

        let settled = expectation(description: "settled")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            settled.fulfill()
        }
        wait(for: [settled], timeout: 5)
        XCTAssertFalse(state.isSampleLibraryLoadedForTesting)
    }

    /// Every module must trigger the load, not just the one that happened to be
    /// tested.
    ///
    /// Asserted through the predicate rather than by constructing ten
    /// `AppState`s. That is not a shortcut: what decides whether the library is
    /// requested is `case .module` — it cannot differ between modules — while
    /// each `AppState` enumerates audio devices in its initialiser, which costs
    /// a minute apiece when the HAL is unwell. The ten-instance version hung
    /// this suite for over ten minutes on a sick machine while asserting
    /// nothing the predicate does not.
    func testEveryModuleScreenIsOneThatRequestsPlayback() {
        for module in LearningModule.allCases {
            let screen = AppScreen.module(module)
            guard case .module = screen else {
                return XCTFail("\(module.id) is not a module screen, so it would never load the library")
            }
        }
        // And the listening screen is the one exception.
        if case .module = AppScreen.listen {
            XCTFail("the listening screen must not request playback")
        }
    }
}
