import SwiftUI

// MARK: - Band mode (D-27)

/// What the bottom band shows. While a guided run is active the corner arrows
/// and the drawer handle are replaced by Stop + the current step (D-27), so
/// the drawer cannot be opened mid-exercise.
enum IOSModuleBandMode: Equatable, Sendable {
    case normal
    case guidedRun
}

/// One corner control of the normal bottom band.
///
/// A `nil` `title` renders the icon-only glass circle the ‹ › step arrows and
/// the icon actions use (Notes' Clear/Play all, Triads Paths' play/stop); a
/// non-nil `title` renders a labelled prominent button (Scales' ▶ Practise).
/// `nil` corner slots are simply not drawn (Scales has no trailing control).
struct IOSModuleBandAction {
    let title: String?
    let systemImage: String
    let accessibilityLabel: String
    let disabled: Bool
    let action: () -> Void
}

extension IOSModuleBandAction {
    /// The icon-only corner: the ‹ › step arrows and Notes'/Triads' icon
    /// actions (D-26/D-22 translucent round buttons).
    static func step(
        systemImage: String,
        accessibilityLabel: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> IOSModuleBandAction {
        IOSModuleBandAction(
            title: nil,
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel,
            disabled: disabled,
            action: action
        )
    }
}

enum IOSModuleBandDecision {
    /// Any non-idle guided-session state — count-in included — counts as a
    /// run: the player has already committed to it. Generic over the step type
    /// so the same decision serves Pentatonic/Scales (`GuidedScaleStep`) and
    /// Triads' progression runs.
    static func mode<Step: Sendable>(guidedStatus: GuidedSession<Step>.Status) -> IOSModuleBandMode {
        guidedStatus == .idle ? .normal : .guidedRun
    }

    /// D-27: a guided run takes the stage and the drawer cannot be reached
    /// mid-exercise, so the drawer closes the moment the band switches to it.
    static func shouldDismissDrawer(transitioningTo mode: IOSModuleBandMode) -> Bool {
        mode == .guidedRun
    }
}

// MARK: - Subtitle / step formatting

/// The one place the subtitle and guided-run step strings are spelled, so the
/// wording can be unit-tested without a view or audio.
enum IOSModuleLandscapeFormat {
    /// "Major 3rd · 4 frets" — the interval's name and its distance in frets.
    static func intervalSubtitle(_ interval: Interval) -> String {
        "\(interval.name) · \(interval.semitones) frets"
    }

    /// "Open · 1 of 5" — the chord position and its place in the voicing list.
    /// Matches the subtitle the Chords landscape screen already showed.
    static func chordsPositionSubtitle(positionLabel: String, positionIndex: Int?, voicingCount: Int) -> String {
        guard let index = positionIndex else { return positionLabel }
        return "\(positionLabel) · \(index + 1) of \(voicingCount)"
    }

    /// "A minor pentatonic · Box 1 of 5".
    static func pentatonicSubtitle(root: PitchClass, quality: PentatonicQuality, box: Int) -> String {
        let qualityName = quality == .minorPentatonic ? "minor" : "major"
        return "\(root.name()) \(qualityName) pentatonic · Box \(box + 1) of 5"
    }

    /// "4 notes placed" — the Notes board's running count.
    static func notesPlacedSubtitle(count: Int) -> String {
        switch count {
        case 0: "No notes placed"
        case 1: "1 note placed"
        default: "\(count) notes placed"
        }
    }

    /// "Position 2 of 5" — where the octave shape sits in its list down the
    /// neck. "Position —" if the shape has no resolvable anchor.
    static func octavesPositionSubtitle(index: Int?, count: Int) -> String {
        guard let index, count > 0 else { return "Position —" }
        return "Position \(index + 1) of \(count)"
    }

    /// "C major · 1st inversion" — the Triads Shapes subtitle. Double stops
    /// have no inversion, so `inversion` is nil and only the pair is named.
    static func triadsShapeSubtitle(root: PitchClass, name: String, inversion: String?) -> String {
        let chord = "\(root.name()) \(name.lowercased())"
        guard let inversion, !inversion.isEmpty else { return chord }
        return "\(chord) · \(inversion)"
    }

    /// "C major · I · 3 of 7" — the Triads Paths subtitle: which diatonic
    /// chord is voiced and how far along the path it sits.
    static func triadsPathSubtitle(chord: String, roman: String, index: Int?, count: Int) -> String {
        let named = "\(chord) · \(roman)"
        guard let index, count > 0 else { return named }
        return "\(named) · \(index + 1) of \(count)"
    }

    /// "Next: C · A string fret 3" (D-27) — the lowest tone of the next path
    /// voicing, so the run's step reads like the guided-scale one does.
    static func triadsPathStepText(next: TriadPathStep?, tuning: Tuning = Tunings.standard) -> String {
        guard let next,
              let tone = next.voicing.tones.min(by: { $0.position.midiNote < $1.position.midiNote })
        else { return "" }
        return "Next: \(next.chord.name) · \(tuning.stringNames[tone.position.string]) string fret \(tone.position.fret)"
    }

    /// "G major" — the selected key.
    static func circleSubtitle(_ key: PitchClass) -> String {
        "\(key.name()) major"
    }

    /// "C major · Ascending" — the scale and the direction a Practise run
    /// walks it (D-26 has no positions for Scales, so direction is the only
    /// thing that moves).
    static func scalesSubtitle(scaleName: String, direction: ScalesModuleModel.Direction) -> String {
        "\(scaleName) · \(direction == .ascending ? "Ascending" : "Up and down")"
    }

    /// "ii · D minor" — the chord of the key in focus, roman degree then name.
    static func harmonizingSubtitle(roman: String, chordName: String) -> String {
        "\(roman) · \(chordName)"
    }

    /// "Over V · G" — the chord underneath the layered neck.
    static func noteAssociationSubtitle(roman: String, chordName: String) -> String {
        "Over \(roman) · \(chordName)"
    }

    /// "Next: D · B string fret 3" (D-27) — the note the hand is moving to.
    static func guidedRunStepText(next: GuidedScaleStep, tuning: Tuning = Tunings.standard) -> String {
        "Next: \(next.pitchClass.name()) · \(tuning.stringNames[next.string]) string fret \(next.fret)"
    }
}

// MARK: - Portrait board strip

/// Sizing and scroll-target math for the portrait board strip (D-06/D-18):
/// the same board view, laid out at a legible per-fret width and scrolled
/// horizontally so the current shape is in view rather than shrunk to fit.
enum IOSModulePortraitStrip {
    /// Column width reserved per fret, so dots stay the size they are on the
    /// landscape neck instead of being uniformly shrunk (D-06).
    static let fretWidth: CGFloat = 44
    /// The board's left gutter (string labels), matching
    /// `BoardGeometry.Margins.labelled.leading`.
    static let leadingMargin: CGFloat = 62
    /// The strip's fixed height: six strings plus the fret-number row.
    static let height: CGFloat = 260
    /// Breathing room left before the target fret, so the shape is not hard
    /// against the leading edge.
    static let leadingInset: CGFloat = 20

    static func width(for frets: Int) -> CGFloat {
        leadingMargin + fretWidth * CGFloat(frets + 1)
    }

    /// The x of a fret's leading edge inside the strip.
    static func leadingEdge(ofFret fret: Int, frets: Int) -> CGFloat {
        leadingMargin + fretWidth * CGFloat(fret)
    }

    /// The scroll offset that brings `fret` into view near the leading edge,
    /// clamped so the strip never scrolls past its end.
    static func scrollOffset(for fret: Int, frets: Int, viewportWidth: CGFloat) -> CGFloat {
        let leading = leadingEdge(ofFret: fret, frets: frets)
        return max(0, min(leading - leadingInset, max(0, width(for: frets) - viewportWidth)))
    }

    /// Which fret the strip should open on: the lowest fret of the emphasised
    /// (outlined) dots — the current shape — falling back to the lowest of all
    /// dots when nothing is outlined (Notes before anything is placed).
    static func focusFret(for dots: [FretboardDot], highestFret: Int) -> Int {
        let emphasised = dots.filter(\.outline)
        let pool = emphasised.isEmpty ? dots : emphasised
        guard let lowest = pool.map(\.position.fret).min() else { return 0 }
        return min(max(lowest, 0), max(highestFret, 0))
    }
}

// MARK: - The primitive

/// The one module layout for both orientations (D-11/D-18): a shared top row
/// of chrome, a centred stage in landscape, and — in portrait — the board as a
/// horizontal scroll strip with the same controls beneath it and the drawer's
/// contents inline as a scrolling page.
///
/// Modules supply their own `neck` (almost always `FretboardBoardView`),
/// `drawer` (the sheet/page content), two optional `leadingAction`/
/// `trailingAction` corners and an optional `companion` (Circle's ring, drawn
/// leading of the board in landscape and above the strip in portrait). The
/// chrome, spacing and band behaviour live here once.
struct IOSModuleScaffold<Neck: View, Companion: View, Drawer: View>: View {
    let title: String
    let subtitle: String
    let tuning: Tuning
    /// Fixed-fret-shape modules (Chords, Pentatonic, Harmonizing) show the
    /// "standard tuning shapes" pill when the global tuning is not standard.
    let isFixedShapeModule: Bool
    let state: AppState
    let neck: Neck
    let companion: Companion
    let leadingAction: IOSModuleBandAction?
    let trailingAction: IOSModuleBandAction?
    let drawerTitle: String
    let drawerSystemImage: String
    let drawer: Drawer
    let bandMode: IOSModuleBandMode
    let guidedRunStepText: String
    let onStopGuidedRun: () -> Void

    /// Called when the global tuning changes, so a module can re-anchor its
    /// shapes (or, for Notes, stop and re-pitch what is placed). Fixed-shape
    /// modules (Chords/Pentatonic/Harmonizing) leave it nil — their frets
    /// detune rather than transpose, which the notice pill explains.
    let onTuningChange: ((Tuning) -> Void)?
    /// The fret count the board draws; sizes the portrait strip so frets stay
    /// legible rather than shrinking.
    let frets: Int
    /// The fret the portrait strip scrolls to, so the current shape is in view.
    let focusFret: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showsDrawer = IOSSnapshot.showsModuleDrawer
    @State private var stripPosition = ScrollPosition(x: 0)

    private var isLandscape: Bool { verticalSizeClass == .compact }

    init(
        title: String,
        subtitle: String,
        tuning: Tuning,
        isFixedShapeModule: Bool,
        state: AppState,
        @ViewBuilder neck: () -> Neck,
        @ViewBuilder companion: () -> Companion = { EmptyView() },
        leadingAction: IOSModuleBandAction?,
        trailingAction: IOSModuleBandAction?,
        drawerTitle: String,
        drawerSystemImage: String,
        @ViewBuilder drawer: () -> Drawer,
        bandMode: IOSModuleBandMode,
        guidedRunStepText: String,
        onStopGuidedRun: @escaping () -> Void,
        onTuningChange: ((Tuning) -> Void)? = nil,
        frets: Int,
        focusFret: Int
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tuning = tuning
        self.isFixedShapeModule = isFixedShapeModule
        self.state = state
        self.neck = neck()
        self.companion = companion()
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
        self.drawerTitle = drawerTitle
        self.drawerSystemImage = drawerSystemImage
        self.drawer = drawer()
        self.bandMode = bandMode
        self.guidedRunStepText = guidedRunStepText
        self.onStopGuidedRun = onStopGuidedRun
        self.onTuningChange = onTuningChange
        self.frets = frets
        self.focusFret = focusFret
    }

    var body: some View {
        Group {
            if isLandscape {
                landscape
            } else {
                portrait
            }
        }
        .onChange(of: state.tuning) { _, tuning in
            onTuningChange?(tuning)
        }
        .onChange(of: bandMode) { _, mode in
            if IOSModuleBandDecision.shouldDismissDrawer(transitioningTo: mode) {
                showsDrawer = false
            }
        }
    }

    // MARK: Landscape

    private var landscape: some View {
        VStack(spacing: 8) {
            topRow
            HStack(alignment: .center, spacing: 20) {
                companion
                neck
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBand
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .sheet(isPresented: $showsDrawer) {
            drawer
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
                .tint(NotePalette.accent)
        }
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            backButton
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            if isFixedShapeModule {
                IOSCompactStandardTuningNotice(tuning: tuning)
            }
            IOSModuleLiveNoteLeaf(state: state, enabled: state.showsLiveNoteOnModules)
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("Back")
    }

    // MARK: Portrait

    private var portrait: some View {
        VStack(alignment: .leading, spacing: 0) {
            subtitleRow
                .padding(.horizontal, 16)
                .padding(.top, 12)
            if isFixedShapeModule {
                IOSCompactStandardTuningNotice(tuning: tuning)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            companion
            boardStrip
                .padding(.top, 8)
            bottomBand
                .padding(.horizontal, 12)
                .padding(.top, 4)
            drawer
                .padding(.top, 8)
        }
        .background(NotePalette.backdrop)
    }

    /// Portrait has no drawer button — the drawer's contents are inline below
    /// the band — so the subtitle takes the title's place under the nav bar
    /// and the live-note leaf stays top-right.
    private var subtitleRow: some View {
        HStack(spacing: 12) {
            Text(subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            IOSModuleLiveNoteLeaf(state: state, enabled: state.showsLiveNoteOnModules)
        }
    }

    private var boardStrip: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                neck
                    .frame(
                        width: IOSModulePortraitStrip.width(for: frets),
                        height: IOSModulePortraitStrip.height
                    )
            }
            .scrollPosition($stripPosition)
            .onAppear { scrollStrip(viewport: proxy.size.width) }
            .onChange(of: focusFret) { scrollStrip(viewport: proxy.size.width) }
            .onChange(of: frets) { scrollStrip(viewport: proxy.size.width) }
        }
        .frame(height: IOSModulePortraitStrip.height)
    }

    private func scrollStrip(viewport: CGFloat) {
        stripPosition = ScrollPosition(
            x: IOSModulePortraitStrip.scrollOffset(
                for: focusFret,
                frets: frets,
                viewportWidth: viewport
            )
        )
    }

    // MARK: Bottom band

    private var bottomBand: some View {
        HStack(spacing: 12) {
            switch bandMode {
            case .normal:
                if let leadingAction {
                    bandActionButton(leadingAction)
                }
                Spacer(minLength: 0)
                if isLandscape {
                    drawerHandle
                }
                Spacer(minLength: 0)
                if let trailingAction {
                    bandActionButton(trailingAction)
                }
            case .guidedRun:
                Button(action: onStopGuidedRun) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .accessibilityLabel("Stop practice run")
                Spacer(minLength: 0)
                Text(guidedRunStepText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
    }

    @ViewBuilder
    private func bandActionButton(_ action: IOSModuleBandAction) -> some View {
        if let title = action.title {
            Button(action: action.action) {
                Label(title, systemImage: action.systemImage)
            }
            .buttonStyle(.glassProminent)
            .tint(NotePalette.accent)
            .disabled(action.disabled)
            .accessibilityLabel(action.accessibilityLabel)
        } else {
            Button(action: action.action) {
                Image(systemName: action.systemImage)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(action.disabled)
            .accessibilityLabel(action.accessibilityLabel)
        }
    }

    private var drawerHandle: some View {
        Button {
            showsDrawer = true
        } label: {
            Label(drawerTitle, systemImage: drawerSystemImage)
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Shared leaves

/// The 008 live-note capsule, rebuilt here as a leaf because the Mac's
/// `ModuleLiveNoteReadout` is private to `ModuleLayout`. Reads `display` only
/// while the feature is on, and owns that read so the rest of the top bar
/// never sees audio-rate invalidations.
struct IOSModuleLiveNoteLeaf: View {
    let state: AppState
    let enabled: Bool

    var body: some View {
        if enabled {
            let display = state.display
            let noteColor = display.note.map { NotePalette.color(for: $0.name) }
            HStack(spacing: 6) {
                Text("LISTENING")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(display.note.map { "\($0.name)\($0.octave)" } ?? "—")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(noteColor?.opacity(0.28) ?? .white.opacity(0.08))
                    }
                    .overlay {
                        Capsule().strokeBorder(noteColor?.opacity(0.52) ?? .white.opacity(0.10), lineWidth: 1)
                    }
            }
            .animation(.easeInOut(duration: 0.2), value: display.note?.midiNote)
        }
    }
}

/// The compact pill version of `StandardTuningNotice` for the landscape top
/// bar.
struct IOSCompactStandardTuningNotice: View {
    let tuning: Tuning

    var body: some View {
        if tuning.id != .standard {
            Label("Standard tuning shapes", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .accessibilityLabel("Standard tuning shapes")
        }
    }
}

/// The "silently mute" guard (CLAUDE.md): playing is a no-op until the sample
/// library is decoded and a player is attached, so say which reason applies
/// instead of letting the Play button fail silently.
struct IOSModulePlaybackNotice: View {
    let state: AppState

    var body: some View {
        if let error = state.samplePlaybackError {
            Label("The note library could not be loaded. \(error)", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if !state.isSamplePlaybackReady {
            Label("Notes will not sound until audio is ready.", systemImage: "speaker.slash.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Nav bar

extension View {
    /// The one nav-bar treatment every iOS module host uses: in portrait the
    /// normal bar (title + gear + back), in landscape the Listen-style empty,
    /// transparent bar so popping back to the list never toggles bar
    /// visibility and re-shoves the list (the measured landscape pop jump).
    func iosModuleNavigationBar(
        title: String,
        isLandscape: Bool,
        isShowingSettings: Binding<Bool>
    ) -> some View {
        self
            .navigationTitle(isLandscape ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isLandscape)
            .toolbarBackgroundVisibility(isLandscape ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                if !isLandscape {
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
