import SwiftUI
import UIKit

/// Direction C shell, split by device idiom rather than size class.
///
/// - **iPhone** (D-21): a `NavigationStack` whose root is the list and whose
///   path starts on `[.listen]`, so the app opens straight into Listen with the
///   list one "back" away — in *both* orientations. A landscape iPhone is
///   regular-width, so the split view would otherwise sit the sidebar beside
///   the detail and eat ~40% of the neck.
/// - **iPad**: a `NavigationSplitView` with the same list as a sidebar.
///
/// The visible screen is kept in step with `AppState.selectedScreen` so the
/// detection gate and lazy sample-playback preparation stay wired exactly as
/// on the Mac (`selectedScreen.didSet` calls both).
///
/// **The list is static chrome and must stay that way (D-08).** It reads the
/// navigation state and nothing else — no detection state, no level, no chord —
/// so an audio-rate read can never invalidate the whole sidebar.
struct IOSPrototypeRootView: View {
    @State private var appState = AppState()
    @State private var path: [AppScreen] = [.listen]
    @State private var selection: AppScreen? = .listen
    @State private var isShowingSettings = false

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        Group {
            if isPhone {
                phoneShell
            } else {
                padShell
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            IOSSettingsSheet(state: appState)
        }
        .tint(NotePalette.accent)
        .preferredColorScheme(.dark)
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

    // MARK: - iPhone (push)

    private var phoneShell: some View {
        NavigationStack(path: $path) {
            phoneList
                .navigationTitle("Fretwork")
                .fretworkSettingsToolbar(isShowingSettings: $isShowingSettings)
                .navigationDestination(for: AppScreen.self) { screen in
                    detail(for: screen)
                }
        }
        .onChange(of: path) { _, newPath in
            appState.selectedScreen = newPath.last ?? .listen
        }
    }

    private var phoneList: some View {
        List {
            Section {
                NavigationLink(value: AppScreen.listen) {
                    rowLabel(for: .listen)
                }
            }
            Section("Learn") {
                ForEach(LearningModule.allCases) { module in
                    NavigationLink(value: AppScreen.module(module)) {
                        rowLabel(for: .module(module))
                    }
                }
            }
        }
    }

    // MARK: - iPad (split)

    private var padShell: some View {
        NavigationSplitView {
            padList
                .navigationTitle("Fretwork")
        } detail: {
            detail(for: selection ?? .listen)
        }
        .onChange(of: selection) { _, newSelection in
            guard let newSelection else { return }
            appState.selectedScreen = newSelection
        }
    }

    private var padList: some View {
        List(selection: $selection) {
            Section {
                rowLabel(for: .listen).tag(AppScreen.listen)
            }
            Section("Learn") {
                ForEach(LearningModule.allCases) { module in
                    rowLabel(for: .module(module)).tag(AppScreen.module(module))
                }
            }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private func detail(for screen: AppScreen) -> some View {
        switch screen {
        case .listen:
            IOSListenScreen(state: appState)
                .navigationTitle("Listen")
                .navigationBarTitleDisplayMode(.inline)
                .fretworkSettingsToolbar(isShowingSettings: $isShowingSettings)
        case .module(.chords):
            IOSChordsScreen(state: appState)
                .navigationTitle("Chords")
                .navigationBarTitleDisplayMode(.inline)
                .fretworkSettingsToolbar(isShowingSettings: $isShowingSettings)
        case .module(let module):
            IOSModulePlaceholder(module: module)
                .navigationTitle(module.title)
                .navigationBarTitleDisplayMode(.inline)
                .fretworkSettingsToolbar(isShowingSettings: $isShowingSettings)
        }
    }

    private func rowLabel(for screen: AppScreen) -> some View {
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
    }
}

private extension View {
    /// The one gear button a screen carries, opening the Settings sheet.
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
