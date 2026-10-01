import SwiftUI
import UIKit

/// The production iOS shell: direction C, split by device idiom (D-24).
///
/// - **iPhone** (D-21): a `NavigationStack` whose root is the list and whose
///   path starts on `[.listen]`, so the app opens straight into Listen with the
///   list one "back" away — in *both* orientations.
/// - **iPad**: a `NavigationSplitView` with the same list as a sidebar.
///
/// The visible screen is kept in step with `AppState.selectedScreen` so the
/// detection gate and lazy sample-playback preparation stay wired exactly as
/// on the Mac (`selectedScreen.didSet` calls both).
///
/// **The list is static chrome and must stay that way (D-08).** It reads the
/// navigation state and nothing else — no detection state, no level, no chord —
/// so an audio-rate read can never invalidate the whole sidebar.
struct IOSAppRootView: View {
    @State private var appState = AppState()
    @State private var path: [AppScreen] = IOSSnapshot.initialPath
    @State private var selection: AppScreen? = .listen
    @State private var isShowingSettings = IOSSnapshot.showsSettingsSheet
    @State private var unlockStore: IOSUnlockStore
    @State private var unlockTarget: LearningModule?
    @State private var showsUnlockSheet = IOSSnapshot.showsUnlockSheet
    #if DEBUG
    @State private var sessionLogger: SessionLogger?
    #endif

    init(unlockStore: IOSUnlockStore = IOSUnlockStore()) {
        _unlockStore = State(initialValue: unlockStore)
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var navigationKind: IOSNavigationKind {
        IOSNavigation.kind(for: UIDevice.current.userInterfaceIdiom)
    }

    /// Landscape on iPhone (compact height) — where the pushed Listen screen
    /// renders its chrome in the (transparent) inline bar. The list's own bar
    /// must be the same inline height there, or the pop transition toggles
    /// between two bar heights and shoves the list down.
    private var isPhoneLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            switch navigationKind {
            case .stack: phoneShell
            case .split: padShell
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            IOSSettingsSheet(state: appState, unlockStore: unlockStore)
        }
        .tint(NotePalette.accent)
        .preferredColorScheme(IOSSnapshot.preferredColorScheme)
        .task {
            unlockStore.start()
            IOSSnapshot.requestLandscapeIfNeeded()
            await unlockStore.refreshEntitlements()
            await unlockStore.loadProduct()
            sanitizeForEntitlements()
            if IOSSnapshot.schedulesPopBack {
                try? await Task.sleep(for: .seconds(2))
                NotificationCenter.default.post(name: IOSSnapshot.popBackNotificationName, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: IOSSnapshot.popBackNotificationName)) { _ in
            path = []
        }
        // The readout resets to neutral whenever the controller is actually
        // stopped (foreground/background, an interruption) rather than holding
        // the last note forever (D-15). Fires once per status transition, not
        // per detector frame.
        .onChange(of: appState.iosAudio?.status) { _, newStatus in
            if newStatus == .idle {
                appState.display = PitchDisplayState()
                appState.chordDisplay = ChordDisplayState()
            }
        }
        // Single observer for the keep-screen-on setting/status/scene decision.
        .fretworkKeepsScreenOn(state: appState)
        #if DEBUG
        .task {
            if CommandLine.arguments.contains("-FretworkSessionLog") {
                let logger = SessionLogger(appState: appState)
                sessionLogger = logger
                logger.start()
            }
        }
        #endif
    }

    // MARK: - iPhone (push)

    private var phoneShell: some View {
        NavigationStack(path: $path) {
            phoneList
                .navigationTitle(isPhoneLandscape ? "" : "Fretwork")
                .navigationBarTitleDisplayMode(isPhoneLandscape ? .inline : .automatic)
                .fretworkSettingsToolbar(isShowingSettings: $isShowingSettings, shows: !isPhoneLandscape)
                .navigationDestination(for: AppScreen.self) { screen in
                    detail(for: screen)
                }
        }
        .onChange(of: path) { _, newPath in
            appState.selectedScreen = newPath.last ?? .listen
        }
        .sheet(isPresented: $showsUnlockSheet) {
            unlockSheet
        }
    }

    private var phoneList: some View {
        List {
            if isPhoneLandscape {
                // In landscape the nav bar is empty (it must match Listen's
                // empty transparent bar so the pop never re-adds a title or
                // trailing item and shifts the list), so the heading and
                // Settings live here in the list content.
                Section {
                    HStack(spacing: 12) {
                        Text("Fretwork")
                            .font(.title.weight(.bold))
                        Spacer()
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Settings")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                NavigationLink(value: AppScreen.listen) {
                    rowLabel(for: .listen)
                }
            }
            Section("Learn") {
                ForEach(LearningModule.allCases) { module in
                    moduleRow(module)
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
        .sheet(isPresented: $showsUnlockSheet) {
            unlockSheet
        }
    }

    private var padList: some View {
        List(selection: $selection) {
            Section {
                rowLabel(for: .listen).tag(AppScreen.listen)
            }
            Section("Learn") {
                ForEach(LearningModule.allCases) { module in
                    if UnlockCatalog.isFree(module) || unlockStore.isUnlocked {
                        rowLabel(for: .module(module)).tag(AppScreen.module(module))
                    } else {
                        Button {
                            unlockTarget = module
                            showsUnlockSheet = true
                        } label: {
                            rowLabel(for: .module(module))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityHint("Opens the unlock options")
                    }
                }
            }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private func detail(for screen: AppScreen) -> some View {
        switch screen {
        case .listen:
            IOSListenScreen(state: appState, isShowingSettings: $isShowingSettings)
        case .module(let module):
            IOSModuleScreen(module: module, state: appState, isShowingSettings: $isShowingSettings)
        }
    }

    @ViewBuilder
    private func moduleRow(_ module: LearningModule) -> some View {
        if UnlockCatalog.isFree(module) || unlockStore.isUnlocked {
            NavigationLink(value: AppScreen.module(module)) {
                rowLabel(for: .module(module))
            }
        } else {
            Button {
                unlockTarget = module
                showsUnlockSheet = true
            } label: {
                rowLabel(for: .module(module))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityHint("Opens the unlock options")
        }
    }

    private var unlockSheet: some View {
        IOSUnlockSheet(store: unlockStore) {
            completeUnlock()
        }
    }

    private func completeUnlock() {
        showsUnlockSheet = false
        guard let module = unlockTarget else { return }
        switch navigationKind {
        case .stack:
            path = [.module(module)]
        case .split:
            selection = .module(module)
        }
    }

    /// D-21: once entitlements are known, a restored path/selection that ends
    /// on a locked module the user does not own falls back to the list.
    private func sanitizeForEntitlements() {
        guard !IOSSnapshot.isActive else { return }
        path = UnlockCatalog.sanitizedPath(path, isUnlocked: unlockStore.isUnlocked)
        if let selection, case .module(let module) = selection,
           !UnlockCatalog.isFree(module), !unlockStore.isUnlocked {
            self.selection = .listen
        }
    }

    private func rowLabel(for screen: AppScreen) -> some View {
        HStack(spacing: 12) {
            Image(systemName: screen.symbol)
                .frame(width: 28)
                .foregroundStyle(NotePalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.title)
                    .foregroundStyle(.primary)
                if case .module(let module) = screen {
                    Text(module.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if case .module(let module) = screen,
               !UnlockCatalog.isFree(module), !unlockStore.isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Locked")
            }
        }
    }
}

private extension View {
    /// The one gear button a screen carries, opening the Settings sheet.
    func fretworkSettingsToolbar(isShowingSettings: Binding<Bool>, shows: Bool = true) -> some View {
        toolbar {
            if shows {
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
}
