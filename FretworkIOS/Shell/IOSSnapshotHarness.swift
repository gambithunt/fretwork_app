#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only deterministic screenshot harness.
///
/// Each `-IOSSnapshot*` launch argument drives one surface into a fixed state
/// so a `simctl io … screenshot` run can capture it without tapping. It skips
/// the real mic session because the iOS 26 simulator ignores the `simctl`
/// microphone grant and re-prompts, covering the chrome.
enum IOSSnapshotHarness {
    enum Scenario: String, CaseIterable {
        case listenPortrait = "-IOSSnapshotListenPortrait"
        case listenLandscape = "-IOSSnapshotListenLandscape"
        case listenLandscapeSidebarClosed = "-IOSSnapshotListenLandscapeSidebarClosed"
        case listenIdle = "-IOSSnapshotListenIdle"
        case listenLiveNoteLandscape = "-IOSSnapshotListenLiveNoteLandscape"
        case listenLiveNotePortrait = "-IOSSnapshotListenLiveNotePortrait"
        case popBack = "-IOSSnapshotPopBack"
        case list = "-IOSSnapshotList"
        case chordsLandscape = "-IOSSnapshotChordsLandscape"
        case chordsDrawer = "-IOSSnapshotChordsDrawer"
        case notesLandscape = "-IOSSnapshotNotesLandscape"
        case notesDrawer = "-IOSSnapshotNotesDrawer"
        case intervalsLandscape = "-IOSSnapshotIntervalsLandscape"
        case intervalsDrawer = "-IOSSnapshotIntervalsDrawer"
        case octavesLandscape = "-IOSSnapshotOctavesLandscape"
        case octavesDrawer = "-IOSSnapshotOctavesDrawer"
        case triadsShapesLandscape = "-IOSSnapshotTriadsShapesLandscape"
        case triadsShapesDrawer = "-IOSSnapshotTriadsShapesDrawer"
        case triadsPathsLandscape = "-IOSSnapshotTriadsPathsLandscape"
        case triadsPathsDrawer = "-IOSSnapshotTriadsPathsDrawer"
        case triadsPathsGuided = "-IOSSnapshotTriadsPathsGuided"
        case pentatonicLandscape = "-IOSSnapshotPentatonicLandscape"
        case pentatonicDrawer = "-IOSSnapshotPentatonicDrawer"
        case pentatonicGuided = "-IOSSnapshotPentatonicGuided"
        case pentatonicGuidedPortrait = "-IOSSnapshotPentatonicGuidedPortrait"
        case scalesLandscape = "-IOSSnapshotScalesLandscape"
        case scalesDrawer = "-IOSSnapshotScalesDrawer"
        case scalesGuided = "-IOSSnapshotScalesGuided"
        case harmonizingLandscape = "-IOSSnapshotHarmonizingLandscape"
        case harmonizingDrawer = "-IOSSnapshotHarmonizingDrawer"
        case noteAssociationLandscape = "-IOSSnapshotNoteAssociationLandscape"
        case noteAssociationDrawer = "-IOSSnapshotNoteAssociationDrawer"
        case circleLandscape = "-IOSSnapshotCircleLandscape"
        case circleDrawer = "-IOSSnapshotCircleDrawer"
        // Portrait module surfaces (D-18): open the module without forcing
        // landscape, so the simulator's default portrait orientation wins.
        case notesPortrait = "-IOSSnapshotNotesPortrait"
        case intervalsPortrait = "-IOSSnapshotIntervalsPortrait"
        case octavesPortrait = "-IOSSnapshotOctavesPortrait"
        case triadsPortrait = "-IOSSnapshotTriadsPortrait"
        case chordsPortrait = "-IOSSnapshotChordsPortrait"
        case pentatonicPortrait = "-IOSSnapshotPentatonicPortrait"
        case scalesPortrait = "-IOSSnapshotScalesPortrait"
        case harmonizingPortrait = "-IOSSnapshotHarmonizingPortrait"
        case noteAssociationPortrait = "-IOSSnapshotNoteAssociationPortrait"
        case circlePortrait = "-IOSSnapshotCirclePortrait"
        case settings = "-IOSSnapshotSettings"
        case permissionDenied = "-IOSSnapshotPermissionDenied"
        case lockedList = "-IOSSnapshotLockedList"
        case lockedListLight = "-IOSSnapshotLockedListLight"
        case unlockSheet = "-IOSSnapshotUnlockSheet"
        case unlockSheetLight = "-IOSSnapshotUnlockSheetLight"
    }

    static var scenario: Scenario? {
        Scenario.allCases.first { CommandLine.arguments.contains($0.rawValue) }
    }

    static var isActive: Bool { scenario != nil }

    /// Never open the real session during a capture: the permission prompt
    /// would sit over the surface being photographed.
    static var shouldSkipAudioSession: Bool { isActive }

    /// The status the pills and banner should render during the capture.
    static var forcedStatus: IOSAudioStatus? {
        switch scenario {
        case .permissionDenied: return .permissionDenied
        case .listenIdle: return .idle
        case .none: return nil
        default: return .listening
        }
    }

    /// The module a scenario opens in landscape, if any.
    static var moduleScenario: LearningModule? {
        switch scenario {
        case .chordsLandscape, .chordsDrawer: return .chords
        case .notesLandscape, .notesDrawer: return .notes
        case .intervalsLandscape, .intervalsDrawer: return .intervals
        case .octavesLandscape, .octavesDrawer: return .octaves
        case .triadsShapesLandscape, .triadsShapesDrawer,
             .triadsPathsLandscape, .triadsPathsDrawer, .triadsPathsGuided: return .triads
        case .pentatonicLandscape, .pentatonicDrawer, .pentatonicGuided, .pentatonicGuidedPortrait: return .pentatonic
        case .scalesLandscape, .scalesDrawer, .scalesGuided: return .scales
        case .harmonizingLandscape, .harmonizingDrawer: return .harmonizing
        case .noteAssociationLandscape, .noteAssociationDrawer: return .noteAssociation
        case .circleLandscape, .circleDrawer: return .circle
        case .notesPortrait: return .notes
        case .intervalsPortrait: return .intervals
        case .octavesPortrait: return .octaves
        case .triadsPortrait: return .triads
        case .chordsPortrait: return .chords
        case .pentatonicPortrait: return .pentatonic
        case .scalesPortrait: return .scales
        case .harmonizingPortrait: return .harmonizing
        case .noteAssociationPortrait: return .noteAssociation
        case .circlePortrait: return .circle
        default: return nil
        }
    }

    static var forcesLandscape: Bool {
        switch scenario {
        case .listenLandscape, .listenLandscapeSidebarClosed, .listenLiveNoteLandscape,
             .popBack, .list,
             .chordsLandscape, .chordsDrawer,
             .notesLandscape, .notesDrawer,
             .intervalsLandscape, .intervalsDrawer,
             .octavesLandscape, .octavesDrawer,
             .triadsShapesLandscape, .triadsShapesDrawer,
             .triadsPathsLandscape, .triadsPathsDrawer, .triadsPathsGuided,
             .pentatonicLandscape, .pentatonicDrawer, .pentatonicGuided,
             .scalesLandscape, .scalesDrawer, .scalesGuided,
             .harmonizingLandscape, .harmonizingDrawer,
             .noteAssociationLandscape, .noteAssociationDrawer,
             .circleLandscape, .circleDrawer:
            return true
        default:
            return false
        }
    }

    /// Whether the harness should pop the navigation stack back to the list
    /// ~2s after launch, so a run can capture the pop transition and the
    /// settled list at fixed offsets.
    static var schedulesPopBack: Bool { scenario == .popBack }


    /// A module snapshot must show its primary action ENABLED. The real path
    /// — decoding the library and building the output-only graph — deadlocks
    /// the headless simulator's audio HAL (Core Audio RPC timeout abort), so
    /// the snapshot marks playback ready directly. DEBUG-only; production
    /// readiness is untouched.
    @MainActor
    static func awaitSamplePlaybackReady(_ state: AppState) async {
        guard moduleScenario != nil else { return }
        state.snapshotMarkSamplePlaybackReady()
    }

    /// Fixed detected content for scenarios whose surface must look alive.
    /// The Listen live-note shots inject A2 (in tune, MIDI 45, 110 Hz) plus an
    /// A-major chord so both readouts are populated for whichever detection
    /// mode is on screen. DEBUG-only; Release never reaches this code.
    @MainActor
    static func applyScenarioState(_ state: AppState) {
        switch scenario {
        case .listenLiveNoteLandscape, .listenLiveNotePortrait:
            state.snapshotInjectListenState(
                note: MappedNote(name: "A", octave: 2, midiNote: 45, cents: 0),
                chord: ChordMatch(root: "A", quality: .major, confidence: 0.85)
            )
        default:
            break
        }
    }

    /// The navigation stack's initial path.
    static var initialPath: [AppScreen] {
        if let module = moduleScenario {
            return [.module(module)]
        }
        switch scenario {
        case .list, .lockedList, .lockedListLight, .unlockSheet, .unlockSheetLight: return []
        default: return [.listen]
        }
    }

    /// The split view's initial selection (iPad), which the iPhone's push path
    /// does not use. Module scenarios force their module so a locked module
    /// still renders (the unlock gate lives in the list, not the detail);
    /// everything else keeps the default Listen selection.
    static var initialSelection: AppScreen? {
        if let module = moduleScenario { return .module(module) }
        return nil
    }

    static var showsSettingsSheet: Bool { scenario == .settings }

    /// Collapses the iPad sidebar so a run can capture the detail at full width
    /// (sidebar closed) alongside the default open state. A standalone launch
    /// argument rather than a scenario, so it composes with every module's
    /// `-IOSSnapshot<Name>Landscape` scenario.
    /// Also set by the Listen sidebar-closed scenario, which predates the
    /// standalone argument.
    static var collapsesSidebar: Bool {
        scenario == .listenLandscapeSidebarClosed
            || CommandLine.arguments.contains("-IOSSnapshotSidebarClosed")
    }
    static var showsUnlockSheet: Bool {
        scenario == .unlockSheet || scenario == .unlockSheetLight
    }

    /// The lock/unlock surfaces follow the app's usual dark scheme; the light
    /// variants flip it so both appearances can be captured.
    static var preferredColorScheme: ColorScheme {
        switch scenario {
        case .lockedListLight, .unlockSheetLight: return .light
        default: return .dark
        }
    }

    static var showsModuleDrawer: Bool {
        switch scenario {
        case .chordsDrawer, .intervalsDrawer, .notesDrawer, .octavesDrawer,
             .triadsShapesDrawer, .triadsPathsDrawer, .pentatonicDrawer,
             .scalesDrawer, .harmonizingDrawer, .noteAssociationDrawer, .circleDrawer:
            return true
        default: return false
        }
    }

    /// Forces the Triads landscape onto its Paths face; the Shapes face is
    /// what the persisted default opens to.
    static var forcesTriadsPathMode: Bool {
        switch scenario {
        case .triadsPathsLandscape, .triadsPathsDrawer, .triadsPathsGuided: return true
        default: return false
        }
    }

    /// Forces a module into its guided-run form (D-27, revised) without
    /// running a real session: the start button renders as ■ Stop, the next-
    /// step text lands in the subtitle, and the other controls dim.
    static var guidedRunActive: Bool {
        scenario == .pentatonicGuided || scenario == .pentatonicGuidedPortrait
            || scenario == .triadsPathsGuided || scenario == .scalesGuided
    }

    static func effectiveStatus(_ actual: IOSAudioStatus?) -> IOSAudioStatus? {
        guard isActive else { return actual }
        return forcedStatus
    }

    /// Requests the orientation the scenario needs. Landscape scenarios force
    /// `.landscapeRight`; everything else forces `.portrait` so a previous
    /// landscape run cannot leak into a portrait capture (the iPad simulator
    /// keeps its orientation across app relaunches, unlike the phone's default).
    @MainActor
    static func requestOrientationIfNeeded() {
        let mask: UIInterfaceOrientationMask = forcesLandscape ? .landscapeRight : .portrait
        Task { @MainActor in
            // A cold launch can reach this before the window scene is
            // connected, and a request made then is silently dropped — the
            // scene keeps its previous orientation. Give the scene a beat to
            // connect, then request once; the iPad sim keeps that orientation
            // across relaunches.
            try? await Task.sleep(for: .milliseconds(500))
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
        }
    }
}
#endif
