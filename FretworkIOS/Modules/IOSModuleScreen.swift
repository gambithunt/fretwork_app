import SwiftUI

/// The one concise title a pushed module shows. Kept short because the
/// landscape scaffold's top row renders the title inline beside the back
/// button, the subtitle, the notice pill and the live-note leaf — the full
/// catalogue title (`LearningModule.title`) is too long there (e.g.
/// "Major, minor & power chords"). Only Chords' Mac nav bar used a short name;
/// this makes every module consistent with that.
enum IOSModuleScreenTitle {
    static func title(for module: LearningModule) -> String {
        switch module {
        case .notes: "Notes"
        case .intervals: "Intervals"
        case .octaves: "Octaves"
        case .triads: "Triads"
        case .chords: "Chords"
        case .pentatonic: "Pentatonic"
        case .scales: "Scales"
        case .harmonizing: "Harmonizing"
        case .noteAssociation: "Note association"
        case .circle: "Circle of fifths"
        }
    }
}

/// Dispatches a pushed `LearningModule` to its iOS screen.
///
/// Every learning module now has a landscape scaffold, so the Listen-style
/// empty/transparent nav bar applies in landscape for all ten — the pop back
/// to the list never toggles bar visibility. Portrait keeps the normal bar
/// (title + gear + back).
struct IOSModuleScreen: View {
    let module: LearningModule
    @Bindable var state: AppState
    @Binding var isShowingSettings: Bool

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// True for every module now that all ten have a scaffold screen.
    private var hasScaffold: Bool {
        switch module {
        case .notes, .intervals, .octaves, .triads, .chords,
             .pentatonic, .scales, .harmonizing, .noteAssociation, .circle: true
        }
    }

    var body: some View {
        content
            .iosModuleNavigationBar(
                title: IOSModuleScreenTitle.title(for: module),
                isLandscape: hasScaffold && isLandscape,
                isShowingSettings: $isShowingSettings
            )
            .background(NotePalette.backdrop)
    }

    @ViewBuilder
    private var content: some View {
        switch module {
        case .notes: IOSNotesScreen(state: state)
        case .intervals: IOSIntervalsScreen(state: state)
        case .octaves: IOSOctavesScreen(state: state)
        case .triads: IOSTriadsScreen(state: state)
        case .chords: IOSChordsScreen(state: state)
        case .pentatonic: IOSPentatonicScreen(state: state)
        case .circle: IOSCircleScreen(state: state)
        case .scales: IOSScalesScreen(state: state)
        case .harmonizing: IOSHarmonizingScreen(state: state)
        case .noteAssociation: IOSNoteAssociationScreen(state: state)
        }
    }
}
