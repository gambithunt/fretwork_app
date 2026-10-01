import AppKit
import SwiftUI
import XCTest
@testable import Fretwork

/// Renders all ten learning module screens to PNGs at the Mac's minimum detail
/// width (950 window − 200 sidebar) and a wide window, so the shared
/// control-card change can be checked on pixels rather than on a diff — the
/// same discipline `DetectionBoardSnapshotTests` applies to the detection
/// board.
///
/// Writes into a directory named by `FRETWORK_SNAPSHOT_DIR`; skips entirely
/// when that is unset, so it costs nothing on an ordinary run. The test runner
/// reaches it as `TEST_RUNNER_FRETWORK_SNAPSHOT_DIR`, which xcodebuild strips
/// the `TEST_RUNNER_` prefix from before the process sees it.
@MainActor
final class ModuleScreenSnapshotTests: XCTestCase {

    /// A deterministic `AppState` off the audio device, so a snapshot run never
    /// contends with the rest of the suite for hardware.
    private func makeState() -> AppState {
        AppState(audio: FakeAudioController(), store: PracticeStateStore(storage: InMemoryPracticeStorage()))
    }

    @ViewBuilder
    private func screen(for module: LearningModule, state: AppState) -> some View {
        switch module {
        case .notes: NotesModuleScreen(state: state)
        case .intervals: IntervalsModuleScreen(state: state)
        case .octaves: OctavesModuleScreen(state: state)
        case .triads: TriadsModuleScreen(state: state)
        case .chords: ChordsModuleScreen(state: state)
        case .pentatonic: PentatonicModuleScreen(state: state)
        case .scales: ScalesModuleScreen(state: state)
        case .harmonizing: HarmonizingModuleScreen(state: state)
        case .noteAssociation: NoteAssociationModuleScreen(state: state)
        case .circle: CircleModuleScreen(state: state)
        }
    }

    func testCaptureAllModuleScreens() throws {
        guard let directory = ProcessInfo.processInfo.environment["FRETWORK_SNAPSHOT_DIR"] else {
            throw XCTSkip("set FRETWORK_SNAPSHOT_DIR to capture")
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for (label, size) in [("min", CGSize(width: 750, height: 1500)), ("wide", CGSize(width: 1300, height: 1200))] {
            for module in LearningModule.allCases {
                let view = screen(for: module, state: makeState())
                    .frame(width: size.width, height: size.height)
                let host = NSHostingView(rootView: view)
                host.frame = CGRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                // `onAppear` builds the model; give the run loop a turn so the
                // pass (and the `@Observable` update it triggers) lands.
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                host.layoutSubtreeIfNeeded()

                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: url.appendingPathComponent("module-\(module.rawValue)-\(label).png"))
            }
        }
    }
}
