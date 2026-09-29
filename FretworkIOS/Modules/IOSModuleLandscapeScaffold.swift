import SwiftUI

// MARK: - Band mode (D-27)

/// What the bottom band shows. While a guided run is active the corner arrows
/// and the drawer handle are replaced by Stop + the current step (D-27), so
/// the drawer cannot be opened mid-exercise.
enum IOSModuleBandMode: Equatable, Sendable {
    case normal
    case guidedRun
}

/// A labelled primary action in the bottom band, in place of a ‹ › step
/// control. Scales has no positions to move along the neck (D-26), so its
/// normal band is a single ▶ Practise button instead of arrows.
struct IOSModuleBandAction {
    let title: String
    let systemImage: String
    let disabled: Bool
    let action: () -> Void
}

enum IOSModuleBandDecision {
    /// Any non-idle guided-session state — count-in included — counts as a
    /// run: the player has already committed to it. Generic over the step type
    /// so the same decision serves Pentatonic/Scales (`GuidedScaleStep`) and
    /// Triads' progression runs.
    static func mode<Step: Sendable>(guidedStatus: GuidedSession<Step>.Status) -> IOSModuleBandMode {
        guidedStatus == .idle ? .normal : .guidedRun
    }
}

// MARK: - Subtitle / step formatting

/// The one place the landscape subtitle and guided-run step strings are
/// spelled, so the wording can be unit-tested without a view or audio.
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

// MARK: - The primitive

/// One shared landscape layout for every learning module (D-11): a top row of
/// chrome (glass back, title + subtitle, the standard-tuning pill, the
/// live-note leaf), a centred stage in the middle, and a bottom band of corner
/// controls plus a drawer button — or, during a guided run, Stop + the current
/// step (D-27).
///
/// Modules supply their own `neck` (almost always `FretboardBoardView`) and
/// `drawer` (the sheet content); the chrome, spacing (D-22: 12pt top, 16pt
/// side, 12pt bottom) and band behaviour live here once.
struct IOSModuleLandscapeScaffold<Neck: View, Drawer: View>: View {
    let title: String
    let subtitle: String
    let tuning: Tuning
    /// Fixed-fret-shape modules (Chords, Pentatonic, Harmonizing) show the
    /// "standard tuning shapes" pill when the global tuning is not standard.
    let isFixedShapeModule: Bool
    let state: AppState
    @ViewBuilder var neck: Neck

    let previousLabel: String
    let previousDisabled: Bool
    let onPrevious: () -> Void
    let nextLabel: String
    let nextDisabled: Bool
    let onNext: () -> Void

    let drawerTitle: String
    let drawerSystemImage: String
    @ViewBuilder var drawer: Drawer

    let bandMode: IOSModuleBandMode
    let guidedRunStepText: String
    let onStopGuidedRun: () -> Void

    /// When set, replaces the leading ‹ arrow in the normal band with a
    /// labelled action (Scales' ▶ Practise). A module with positions to step
    /// through leaves it `nil` and keeps the arrows.
    var primaryAction: IOSModuleBandAction? = nil
    /// Whether the normal band draws the ‹ › step arrows at all. A module with
    /// no positions along the neck (Scales) passes `false`.
    var showsStepControls = true

    @Environment(\.dismiss) private var dismiss
    @State private var showsDrawer = IOSSnapshot.showsModuleDrawer

    var body: some View {
        VStack(spacing: 8) {
            topRow
            neck
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

    // MARK: Top row

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

    // MARK: Bottom band

    private var bottomBand: some View {
        HStack(spacing: 12) {
            switch bandMode {
            case .normal:
                if let primaryAction {
                    actionButton(primaryAction)
                } else if showsStepControls {
                    cornerButton(systemImage: "chevron.left", label: previousLabel, disabled: previousDisabled, action: onPrevious)
                }
                Spacer(minLength: 0)
                drawerHandle
                Spacer(minLength: 0)
                if showsStepControls {
                    cornerButton(systemImage: "chevron.right", label: nextLabel, disabled: nextDisabled, action: onNext)
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

    private func actionButton(_ action: IOSModuleBandAction) -> some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.systemImage)
        }
        .buttonStyle(.glassProminent)
        .tint(NotePalette.accent)
        .disabled(action.disabled)
    }

    private func cornerButton(systemImage: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(disabled)
        .accessibilityLabel(label)
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
