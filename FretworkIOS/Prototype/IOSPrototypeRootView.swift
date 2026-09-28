import SwiftUI

/// Direction C shell: a `NavigationSplitView` whose sidebar mirrors the Mac's
/// list — Listen plus the ten learning modules — with Settings as a sheet from
/// the toolbar.
///
/// The visible selection is local list state; `AppState.selectedScreen` is
/// kept in step with it so the detection gate and lazy sample-playback
/// preparation stay wired exactly as on the Mac (`selectedScreen.didSet` calls
/// both). The initial selection of `.listen` makes Listen the screen the app
/// opens on (D-21), with the list one "back" away.
///
/// **The list is static chrome and must stay that way (D-08).** It reads
/// `selection` and nothing else — no detection state, no level, no chord — so
/// an audio-rate read can never invalidate the whole sidebar.
struct IOSPrototypeRootView: View {
    @State private var appState = AppState()
    @State private var selection: AppScreen? = .listen
    @State private var isShowingSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    row(for: .listen)
                }
                Section("Learn") {
                    ForEach(LearningModule.allCases) { module in
                        row(for: .module(module))
                    }
                }
            }
            .navigationTitle("Fretwork")
            .fretworkSettingsToolbar(isShowingSettings: $isShowingSettings)
        } detail: {
            detail
                .fretworkSettingsToolbar(isShowingSettings: $isShowingSettings)
        }
        .sheet(isPresented: $isShowingSettings) {
            IOSSettingsSheet(state: appState)
        }
        .tint(NotePalette.accent)
        .preferredColorScheme(.dark)
        .onChange(of: selection) { _, newSelection in
            guard let newSelection else { return }
            appState.selectedScreen = newSelection
        }
        // The readout resets to neutral whenever the controller is actually
        // stopped (foreground/background, an interruption) rather than holding
        // the last note forever (D-15). Audio-rate neutral: fires once per
        // status transition, not per detector frame.
        .onChange(of: appState.iosAudio?.status) { _, newStatus in
            if newStatus == .idle {
                appState.display = PitchDisplayState()
                appState.chordDisplay = ChordDisplayState()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .listen {
        case .listen:
            IOSListenScreen(state: appState)
                .navigationTitle("Listen")
                .navigationBarTitleDisplayMode(.inline)
        case .module(.chords):
            IOSChordsScreen(state: appState)
                .navigationTitle("Chords")
                .navigationBarTitleDisplayMode(.inline)
        case .module(let module):
            IOSModulePlaceholder(module: module)
                .navigationTitle(module.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(for screen: AppScreen) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.title)
                if case .module(let module) = screen {
                    Text(module.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: screen.symbol)
        }
        .tag(screen)
    }
}

private extension View {
    /// The gear button both the sidebar and the detail carry, opening the
    /// Settings sheet.
    func fretworkSettingsToolbar(isShowingSettings: Binding<Bool>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings.wrappedValue = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}
