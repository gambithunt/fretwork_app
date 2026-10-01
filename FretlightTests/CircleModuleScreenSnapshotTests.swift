import AppKit
import SwiftUI
import XCTest
@testable import Fretwork

/// Renders `CircleModuleScreen` to a PNG so a spelling change to the ring,
/// the selected key title, or the triad board can be judged on pixels rather
/// than on a diff — the same discipline `DetectionBoardSnapshotTests` applies
/// to the detection board.
///
/// The store is seeded with E♭ so the run exercises a flat key: its title,
/// its board labels and the flat half of the ring are all in the frame.
///
/// Writes into a directory named by `FRETWORK_SNAPSHOT_DIR`; skips entirely
/// when that is unset, so it costs nothing on an ordinary run.
@MainActor
final class CircleModuleScreenSnapshotTests: XCTestCase {
    private func makeState() -> AppState {
        let store = PracticeStateStore(storage: InMemoryPracticeStorage())
        store.update { $0.modules.circle.selectedPitchClass = 3 }
        return AppState(audio: FakeAudioController(), store: store)
    }

    func testCaptureCircleModuleScreen() throws {
        guard let directory = ProcessInfo.processInfo.environment["FRETWORK_SNAPSHOT_DIR"] else {
            throw XCTSkip("set FRETWORK_SNAPSHOT_DIR to capture")
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let size = CGSize(width: 1100, height: 1300)
        let view = CircleModuleScreen(state: makeState()).frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // `onAppear` builds the model; give the run loop a turn so that pass
        // (and the `@Observable` update it triggers) lands before the cache.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("circle-screen.png"))
    }
}
