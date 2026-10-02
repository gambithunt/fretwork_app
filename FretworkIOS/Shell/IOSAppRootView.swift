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
    @State private var selection: AppScreen? = IOSSnapshot.initialSelection ?? .listen
    @State private var isShowingSettings = IOSSnapshot.showsSettingsSheet
    @State private var unlockStore: IOSUnlockStore
    @State private var unlockTarget: LearningModule?
    @State private var showsUnlockSheet = IOSSnapshot.showsUnlockSheet
    /// The iPad split view's sidebar state; the snapshot harness collapses it
    /// for the sidebar-closed capture. `.automatic` everywhere else. The glide
    /// capture forces `.all` from the first render so the sidebar column is
    /// guaranteed visible (`.automatic` can restore a collapsed icon rail).
    @State private var columnVisibility: NavigationSplitViewVisibility = {
        #if DEBUG
        if IOSSidebarGlideCapture.isActive { return .all }
        #endif
        return IOSSnapshot.collapsesSidebar ? .detailOnly : .automatic
    }()
    #if DEBUG
    @State private var sessionLogger: SessionLogger?
    @State private var glideCaptureRunning = false
    #endif

    init(unlockStore: IOSUnlockStore = IOSUnlockStore()) {
        _unlockStore = State(initialValue: unlockStore)
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Namespace for the one sidebar selection highlight that slides between
    /// rows (`matchedGeometryEffect`) instead of jumping.
    @Namespace private var sidebarHighlightNamespace

    private var navigationKind: IOSNavigationKind {
        IOSNavigation.kind(for: UIDevice.current.userInterfaceIdiom)
    }

    /// Landscape on iPhone (compact height) — where the pushed Listen screen
    /// renders its chrome in the (transparent) inline bar. The list's own bar
    /// must be the same inline height there, or the pop transition toggles
    /// between two bar heights and shoves the list down.
    private var isPhoneLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch navigationKind {
                case .stack: phoneShell
                case .split: padShell
                }
            }
            .environment(
                \.fretworkIsLandscape,
                IOSOrientation.isLandscape(
                    idiom: UIDevice.current.userInterfaceIdiom,
                    verticalSizeClass: verticalSizeClass,
                    viewportWidth: proxy.size.width,
                    viewportHeight: proxy.size.height
                )
            )
            .sheet(isPresented: $isShowingSettings) {
                IOSSettingsSheet(state: appState, unlockStore: unlockStore)
            }
            .tint(NotePalette.accent)
            .preferredColorScheme(IOSSnapshot.preferredColorScheme)
            .task {
                unlockStore.start()
                IOSSnapshot.requestOrientationIfNeeded()
                // Sync the snapshot's initial selection/path to `selectedScreen`
                // so the playback-preparation gate (`selectedScreen.didSet`)
                // fires for the initial value — `onChange` never fires for a
                // pre-set selection, and without this the hosted module
                // screens' `prepareSamplePlayback` never runs (the silent-mute
                // bug). A no-op in production, where both start at `.listen`.
                appState.selectedScreen = selection ?? path.last ?? .listen
                #if DEBUG
                if IOSSnapshot.isActive {
                    // The Mac screenshot shows the live-note capsule because
                    // its setting was on; mirror that so iPad module shots
                    // exercise the same capsule.
                    appState.showsLiveNoteOnModules = true
                    // A module snapshot must show its primary action enabled:
                    // wait until sample playback is actually ready before the
                    // capture settles (the module screens request it lazily).
                    await IOSSnapshot.awaitSamplePlaybackReady(appState)
                }
                #endif
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
            #if DEBUG
            // Selection-highlight glide capture: the notification is posted by
            // the `-IOSSidebarGlideCapture` task below, never by a synthetic
            // tap (CLAUDE.md workflow 6 — they don't drive SwiftUI selection).
            .onReceive(NotificationCenter.default.publisher(for: IOSSidebarGlideCapture.notification)) { _ in
                guard !glideCaptureRunning else { return }
                glideCaptureRunning = true
                // Capture a few resting frames first (Listen selected), then
                // trigger the slide inside the recorder, so the recording shows
                // the detail pane change together with the highlight's slide.
                Task { @MainActor in
                    await IOSSidebarGlideCapture.record(seconds: 2.6, preFrames: 5) {
                        withAnimation(FretworkMotion.gravity) {
                            selection = IOSSidebarGlideCapture.target
                        }
                    }
                    glideCaptureRunning = false
                }
            }
            #endif
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
                if IOSSidebarGlideCapture.isActive {
                    // Force landscape so the sidebar column is visible (it
                    // collapses in portrait). The split is already forced to
                    // `.all` by the columnVisibility initialiser above.
                    IOSSidebarGlideCapture.requestLandscape()
                    // Settle so the opening frame shows the highlight at rest on
                    // Listen — no slide-in on first appearance — before posting
                    // the trigger once. The landscape rotation request above
                    // retries over ~6 s and then needs a moment to land, so give
                    // it a full 10 s.
                    try? await Task.sleep(for: .seconds(10))
                    NotificationCenter.default.post(name: IOSSidebarGlideCapture.notification, object: nil)
                }
            }
            #endif
        }
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
        // A ScrollView + VStack rather than `List(selection:)`: the List renders
        // rows through the table view's cell path, which does not re-parent a
        // matchedGeometryEffect row background when the selection changes, so the
        // highlight never moved. The VStack is small (eleven static rows) and
        // re-parents the one background normally. Selection semantics are manual:
        // each row is a Button, and the selected one carries `.isSelected`.
        ScrollView {
            VStack(spacing: 0) {
                sidebarRow(for: .listen)
                sidebarSectionHeader("Learn")
                ForEach(LearningModule.allCases) { module in
                    if UnlockCatalog.isFree(module) || unlockStore.isUnlocked {
                        sidebarRow(for: .module(module))
                    } else {
                        lockedSidebarRow(module)
                    }
                }
            }
            // Symmetric capsule insets. The sidebar column adds ~10 pt on the
            // leading edge of its own, so compensate with an extra ~10 pt on
            // the trailing edge to keep the capsule centred.
            .padding(.leading, 6)
            .padding(.trailing, 16)
        }
        .background {
            // Adaptive: the exact dark the system sidebar drew, or the light
            // grouped background in light mode (the snapshot's light variants).
            colorScheme == .dark
                ? Color(red: 0.075, green: 0.078, blue: 0.082)
                : Color(uiColor: .secondarySystemGroupedBackground)
        }
        // The slide and the text/icon colour change happen in this one
        // transaction, under the same gravity spring as every module control.
        // Reduce Motion turns the slide into an instant move.
        .animation(reduceMotion ? nil : FretworkMotion.gravity, value: selection)
    }

    /// A selectable sidebar row. Its background carries the one sliding
    /// highlight (re-parented with `matchedGeometryEffect`), and the selected
    /// row reports `.isSelected` for VoiceOver. Locked rows never reach this
    /// path — their tap opens the unlock sheet and the highlight must not move.
    private func sidebarRow(for screen: AppScreen) -> some View {
        let isSelected = selection == screen
        return Button {
            selection = screen
        } label: {
            rowLabel(for: screen, isSelected: isSelected)
                .padding(.leading, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.vertical, 11)
        .background {
            if isSelected {
                SidebarSelectionHighlight()
                    .matchedGeometryEffect(id: "sidebar-selection", in: sidebarHighlightNamespace)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A locked module row: the same layout as a selectable row, but the tap
    /// opens the unlock sheet and never changes the selection (so the highlight
    /// never moves to a locked row).
    private func lockedSidebarRow(_ module: LearningModule) -> some View {
        Button {
            unlockTarget = module
            showsUnlockSheet = true
        } label: {
            rowLabel(for: .module(module))
                .padding(.leading, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.vertical, 11)
        .accessibilityHint("Opens the unlock options")
    }

    /// The "Learn" section heading, aligned with the rows' icon.
    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 22)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func rowLabel(for screen: AppScreen, isSelected: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: screen.symbol)
                .frame(width: 28)
                .foregroundStyle(NotePalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.title)
                    .foregroundStyle(isSelected ? NotePalette.accent : Color.primary)
                if case .module(let module) = screen {
                    Text(module.blurb)
                        .font(.caption)
                        // Semantic secondary — adapts to light and dark. The
                        // capsule behind the selected row lifts it slightly.
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
