import AppKit
import SwiftUI
import XCTest
@testable import Fretwork

/// The owner's D-27 guarantee, as a test: starting or stopping a run must not
/// change the control card's height. Each module that runs a guided
/// progression/practise has its controls rendered idle, counting in, and
/// mid-run at both the Mac minimum detail width and a wide window, and the
/// rendered height is asserted equal across the three states.
///
/// The run state is pinned through each model's DEBUG-only `debugForceRun`
/// (never compiled into Release), which fabricates the snapshot directly so no
/// real clock keeps racing the measurement. The controls are built by the same
/// `controls` builders the screens use, then measured with
/// `NSHostingView.fittingSize` — the same technique the window's min/max sizes
/// were derived with — so nothing depends on the accessibility subtree or a
/// preference inside the scroll view.
@MainActor
final class ModuleControlCardStabilityTests: XCTestCase {

    private func controlCardHeight(
        module: LearningModule,
        width: CGFloat,
        run: ModuleRunSnapshot.ForcedRun
    ) -> CGFloat {
        let store = PracticeStateStore(storage: InMemoryPracticeStorage())
        let play: (FretPosition) -> Void = { _ in }
        let tuning = Tunings.standard
        let controls: AnyView

        switch module {
        case .noteAssociation:
            let model = NoteAssociationModuleModel(tuning: tuning, store: store, play: play)
            model.debugForceRun(run)
            controls = AnyView(NoteAssociationModuleScreen.controls(model))
        case .triads:
            let model = TriadsModuleModel(tuning: tuning, store: store, play: play)
            model.debugForceRun(run)
            controls = AnyView(TriadsModuleScreen.controls(model, labelMode: .constant(.degrees)))
        case .pentatonic:
            let model = PentatonicModuleModel(store: store, play: play)
            model.debugForceRun(run)
            controls = AnyView(PentatonicModuleScreen.controls(model, labelMode: .constant(.degrees)))
        case .scales:
            let model = ScalesModuleModel(tuning: tuning, store: store, play: play)
            model.debugForceRun(run)
            controls = AnyView(ScalesModuleScreen.controls(model))
        default:
            fatalError("\(module.rawValue) has no guided run")
        }

        let host = NSHostingView(rootView: controls.frame(width: width))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testControlCardHeightIsStableAcrossRunStates() {
        for width in [CGFloat(750), CGFloat(1300)] {
            for module in [LearningModule.noteAssociation, .triads, .pentatonic, .scales] {
                let idle = controlCardHeight(module: module, width: width, run: .idle)
                let countIn = controlCardHeight(module: module, width: width, run: .countIn)
                let playing = controlCardHeight(module: module, width: width, run: .playing)

                XCTAssertGreaterThan(
                    idle, 0,
                    "controls must report a height for \(module.rawValue) at \(Int(width))pt"
                )
                XCTAssertEqual(
                    idle, countIn, accuracy: 0.5,
                    "\(module.rawValue)@\(Int(width)): idle vs count-in card height"
                )
                XCTAssertEqual(
                    idle, playing, accuracy: 0.5,
                    "\(module.rawValue)@\(Int(width)): idle vs mid-run card height"
                )
            }
        }
    }
}
