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

    /// Every module that sounds notes must trigger the load, not just the one
    /// that happened to be tested.
    func testEveryModuleLoadsTheLibrary() {
        for module in LearningModule.allCases {
            let state = AppState()
            state.selectedScreen = .module(module)

            let loaded = expectation(description: "library for \(module.id)")
            Task { @MainActor in
                for _ in 0..<200 {
                    if state.isSampleLibraryLoadedForTesting { return loaded.fulfill() }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            wait(for: [loaded], timeout: 30)
        }
    }
}
