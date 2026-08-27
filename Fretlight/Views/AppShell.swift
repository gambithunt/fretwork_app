import SwiftUI

/// The window's navigation: a sidebar listing the listening screen and the ten
/// learning modules, with the selected screen beside it.
///
/// **The sidebar is static chrome and must stay that way.** It reads
/// `selection` and nothing else — no detection state, no level, no chord. That
/// is not a style preference: `@Observable` tracks reads per view body, so one
/// audio-rate property read here would invalidate the whole sidebar around 30
/// times a second, and `CLAUDE.md` records a measured leak of ~1800
/// `ObservationRegistrar` contexts per 30 s from rebuilding a picker at that
/// rate, with per-update cost growing as uptime grows. At the top level of the
/// view tree that cost would apply to everything.
///
/// **Audio does not restart on navigation.** The engine is started once, by
/// `ContentView`, and lives on `AppState` for the window's lifetime. Screens
/// come and go around it. `AudioEngine` already treats a restart as a recovery
/// event with a debounce and an attempt cap, because an uncapped restart loop
/// was a real bug; navigation must never reach that path.
struct AppShell: View {
    /// The sidebar's floor. Part of the window's own minimum width, which is
    /// this plus whatever the detail screen needs — see `FretlightApp`.
    static let sidebarMinimumWidth: CGFloat = 200

    @Bindable var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedScreen) {
                Section {
                    row(for: .listen)
                }
                Section("Learn") {
                    ForEach(LearningModule.allCases) { module in
                        row(for: .module(module))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: Self.sidebarMinimumWidth, ideal: 220, max: 280)
        } detail: {
            switch state.selectedScreen {
            case .listen:
                ListenScreen(state: state)
            case .module(.notes):
                NotesModuleScreen(state: state)
            case .module(.intervals):
                IntervalsModuleScreen(state: state)
            case .module(.octaves):
                OctavesModuleScreen(state: state)
            case .module(.triads):
                TriadsModuleScreen(state: state)
            case .module(.chords):
                ChordsModuleScreen(state: state)
            case .module(let module):
                ModulePlaceholderScreen(module: module)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("Devices, monitoring, tuning and board orientation")
                .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                    GlobalSettingsView(state: state)
                }
            }
        }
    }

    @State private var isShowingSettings = false

    private func row(for screen: AppScreen) -> some View {
        Label(screen.title, systemImage: screen.symbol)
            .tag(screen)
    }
}

/// Stands in for a module until workstream 006 builds it.
///
/// Deliberately shows the module's real title, blurb and board ceiling rather
/// than the word "placeholder": those come from the catalogue that mirrors the
/// web app, so a wrong title or a module in the wrong place is visible now
/// rather than after ten screens are built on top of it.
struct ModulePlaceholderScreen: View {
    let module: LearningModule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(module.title)
                .font(.largeTitle.weight(.semibold))
            Text(module.blurb)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Board goes to fret \(module.highestFret)", systemImage: "ruler")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
        .background(Color(red: 0.035, green: 0.045, blue: 0.047))
        .preferredColorScheme(.dark)
    }
}
