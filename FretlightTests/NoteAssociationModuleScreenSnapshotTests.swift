import AppKit
import SwiftUI
import XCTest
@testable import Fretwork

/// Renders `NoteAssociationModuleScreen` to a PNG so a visible control change
/// (the macOS-only checkbox toggles becoming chips) can be judged on pixels
/// rather than on a diff — the same discipline `DetectionBoardSnapshotTests`
/// applies to the detection board.
///
/// Writes into a directory named by `FRETWORK_SNAPSHOT_DIR`; skips entirely
/// when that is unset, so it costs nothing on an ordinary run. The test runner
/// reaches it as `TEST_RUNNER_FRETWORK_SNAPSHOT_DIR`, which xcodebuild strips
/// the `TEST_RUNNER_` prefix from before the process sees it.
@MainActor
final class NoteAssociationModuleScreenSnapshotTests: XCTestCase {

    /// A deterministic `AppState`: the injected fake controller keeps this off
    /// the audio device, so a snapshot run never contends with the rest of the
    /// suite for hardware, and the in-memory store lets the layer/loop state be
    /// seeded exactly (some on, some off) without touching a real defaults
    /// domain.
    private func makeState() -> AppState {
        let store = PracticeStateStore(storage: InMemoryPracticeStorage())
        store.update {
            $0.modules.noteAssociation.showsChordTones = true
            $0.modules.noteAssociation.showsPentatonic = false
            $0.modules.noteAssociation.showsScale = true
            $0.modules.noteAssociation.loop = true
        }
        return AppState(audio: FakeAudioController(), store: store)
    }

    func testCaptureNoteAssociationModuleScreen() throws {
        guard let directory = ProcessInfo.processInfo.environment["FRETWORK_SNAPSHOT_DIR"] else {
            throw XCTSkip("set FRETWORK_SNAPSHOT_DIR to capture")
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let view = NoteAssociationModuleScreen(state: makeState())
            .frame(width: 1000, height: 1400)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        host.layoutSubtreeIfNeeded()
        // `onAppear` builds the model; give the run loop a turn so the
        // `.onAppear` pass (and the `@Observable` update it triggers) lands
        // before the cache is taken.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("note-association-screen.png"))
    }
}
