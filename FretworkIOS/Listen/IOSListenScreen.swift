import Foundation
import SwiftUI

/// The iOS Listen screen.
///
/// Portrait is a pure tuner (D-16): no fretboard — just the note/chord
/// readout, cents·Hz, input level, history and a quiet rotate hint. Landscape
/// is a single native chrome row (back, Listening pill, live-note pill,
/// segmented, gear) over the full 22-fret neck (D-17, D-22).
///
/// **Audio-rate reads live only in the small leaf views below.** The parent
/// body reads `detectionMode` (changes on tap), orientation and the
/// event-driven iOS status only — never `display`, `chordDisplay` or the
/// history arrays (D-08).
struct IOSListenScreen: View {
    @Bindable var state: AppState
    @Binding var isShowingSettings: Bool

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isLandscape {
                landscape
            } else {
                portrait
            }
        }
        .background(NotePalette.backdrop)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(isLandscape ? "" : "Listen")
        // Landscape keeps the nav bar PRESENT (so popping back to the list
        // never toggles bar visibility and re-shoves the list) but renders it
        // empty and transparent: no back button, no title, no system items,
        // no background. The custom glass row is drawn as content inside that
        // same band via `.ignoresSafeArea(.container, edges: .top)` below, so
        // the board's position does not change.
        .navigationBarBackButtonHidden(isLandscape)
        .toolbarBackgroundVisibility(isLandscape ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if !isLandscape {
                ToolbarItem(placement: .topBarTrailing) {
                    gearButton
                }
            }
        }
        .task {
            attemptStartIfIdle()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Recovery (D-10): after granting in Settings, or an interruption
            // that ends without shouldResume, the controller sits .idle; the
            // returning .active re-arms it.
            if newPhase == .active { attemptStartIfIdle() }
        }
    }

    // MARK: - Portrait

    private var portrait: some View {
        // Optical-centre placement (D-16 polish): a fixed 24pt gap under the
        // status row, then the note group, then the remaining flexible space
        // split 1 part above : 2 parts below the note group — three equal
        // spacers put one share above and two below, so the note sits slightly
        // higher than the geometric centre instead of sinking.
        VStack(spacing: 0) {
            headerRow
            statusBanner
            startListeningControl
            Color.clear.frame(height: 24)
            Spacer(minLength: 0)
            readout
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            inputLevel
            Color.clear.frame(height: 12)
            history
            Color.clear.frame(height: 12)
            rotateHint
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Landscape

    private var landscape: some View {
        VStack(spacing: 0) {
            landscapeTopBar
            statusBanner
            startListeningControl
            IOSBoardLeaf(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// The single landscape chrome row, drawn as content (not toolbar items).
    /// The glass container groups the pills; an HStack inside keeps them on one
    /// horizontal line with explicit gaps so no pill shares another's glass.
    private var landscapeTopBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                landscapeBackButton
                IOSLandscapeListeningPill(state: state)
                Spacer(minLength: 0)
                liveNotePill
                Spacer(minLength: 0)
                detectionModePicker
                landscapeGearButton
            }
        }
    }

    private var landscapeBackButton: some View {
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

    private var landscapeGearButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("Settings")
    }

    @ViewBuilder
    private var liveNotePill: some View {
        if state.detectionMode == .notes {
            IOSLandscapeNotePill(state: state)
        } else {
            IOSLandscapeChordPill(state: state)
        }
    }

    private var headerRow: some View {
        HStack {
            IOSStatusPill(state: state)
            Spacer()
            detectionModePicker
        }
    }

    private var detectionModePicker: some View {
        Picker("Detection mode", selection: $state.detectionMode) {
            ForEach(DetectionMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
    }

    private var gearButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }

    @ViewBuilder
    private var readout: some View {
        switch state.detectionMode {
        case .notes:
            IOSNotesTunerReadout(state: state)
        case .chords:
            IOSChordsTunerReadout(state: state)
        }
    }

    private var inputLevel: some View {
        IOSInputLevelLeaf(state: state, mode: state.detectionMode)
    }

    private var history: some View {
        IOSHistoryLeaf(state: state, mode: state.detectionMode)
    }

    private var rotateHint: some View {
        HStack(spacing: 9) {
            Image(systemName: "rotate.right")
            Text("Turn your phone to see it on the neck")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var statusBanner: some View {
        let status = IOSSnapshot.effectiveStatus(state.iosAudio?.status)
        switch IOSStatusSurfaceMapper.surface(for: status) {
        case .none:
            EmptyView()
        case .permissionDenied:
            IOSStatusBanner(
                title: "Microphone access is off",
                message: "Fretwork listens to your guitar to identify notes. Turn on microphone access in Settings to start listening.",
                systemImage: "mic.slash.fill",
                tint: .red
            ) {
                Button("Open Settings") { openSettings() }
                    .buttonStyle(.glass)
            }
        case .interrupted:
            IOSStatusBanner(
                title: "Paused",
                message: "Audio will resume automatically.",
                systemImage: "pause.circle.fill",
                tint: .orange
            )
        case .failed(let message):
            IOSStatusBanner(
                title: "Audio unavailable",
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red
            ) {
                Button("Retry") { state.retryAudio() }
                    .buttonStyle(.glass)
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Start once on first appear, and re-arm after a background/foreground
    /// cycle that left the controller idle (permission grant, an interruption
    /// without shouldResume). Snapshot captures never touch the real session.
    private func attemptStartIfIdle() {
        guard !IOSSnapshot.shouldSkipAudioSession else { return }
        if IOSStartDecision.shouldStart(
            status: state.iosAudio?.status,
            permission: state.iosAudio?.recordPermission,
            sceneActive: scenePhase == .active
        ) {
            state.start()
        }
    }

    /// An explicit recovery path in the `.idle` state, so a stopped listener
    /// never depends on scene re-activation alone.
    @ViewBuilder
    private var startListeningControl: some View {
        if IOSSnapshot.effectiveStatus(state.iosAudio?.status) == .idle {
            HStack(spacing: 12) {
                Text("Listening is stopped.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start listening") {
                    state.start()
                }
                .buttonStyle(.glassProminent)
                .tint(NotePalette.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Leaves (one per audio-rate read)

/// The event-driven listening status, as a small pill. Reads the iOS
/// controller's status — not the audio-rate `display`.
private struct IOSStatusPill: View {
    let state: AppState

    var body: some View {
        let appearance = IOSStatusAppearanceMapper.appearance(
            for: IOSSnapshot.effectiveStatus(state.iosAudio?.status)
        )
        HStack(spacing: 8) {
            Circle()
                .fill(appearance.tint)
                .frame(width: 6, height: 6)
                .shadow(color: appearance.tint.opacity(0.9), radius: 4)
            Text(appearance.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: appearance.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appearance.title)
    }
}

/// Landscape "● Listening" pill, drawn as content (not a toolbar item, whose
/// icon-collapse dropped the title on device). An HStack of the pulsing dot
/// and the text inside a native glass capsule. The dot pulses with level
/// (static under Reduce Motion).
private struct IOSLandscapeListeningPill: View {
    let state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let appearance = IOSStatusAppearanceMapper.appearance(
            for: IOSSnapshot.effectiveStatus(state.iosAudio?.status)
        )
        let scale = IOSReadoutFormat.pulseScale(
            normalizedLevel: IOSReadoutFormat.normalizedLevel(state.display.level),
            reduceMotion: reduceMotion
        )

        HStack(spacing: 6) {
            Circle()
                .fill(appearance.tint)
                .frame(width: 6, height: 6)
                .scaleEffect(scale)
                .shadow(color: appearance.tint.opacity(0.9), radius: 4)
            Text(appearance.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(in: .capsule)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: scale)
        .animation(.easeInOut(duration: 0.2), value: appearance.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appearance.title)
    }
}

/// Centred live-note pill for the landscape nav bar (Notes mode): note name +
/// octave in a pitch-class-tinted capsule with cents inline — green when
/// |cents| ≤ 5, neutral otherwise, an em-dash when silent. Owns the `display`
/// read.
private struct IOSLandscapeNotePill: View {
    let state: AppState

    var body: some View {
        let note = state.display.note
        let tint = note.map { NotePalette.color(for: $0.name) } ?? Color.white.opacity(0.14)
        let centsColor: Color = IOSReadoutFormat.centsTint(note?.cents) == .inTune ? .green : .secondary

        HStack(spacing: 6) {
            if note != nil {
                Text(IOSReadoutFormat.noteLabel(note))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(IOSReadoutFormat.centsText(note?.cents))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(centsColor)
            } else {
                Text("—")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.28)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.2), value: note?.midiNote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.map { "Live note \($0.name)\($0.octave)" } ?? "Listening for a note")
    }
}

/// Centred live-note pill for the landscape nav bar (Chords mode): the chord
/// name in a root-tinted capsule, an em-dash when silent. Owns the
/// `chordDisplay` read.
private struct IOSLandscapeChordPill: View {
    let state: AppState

    var body: some View {
        let chord = state.chordDisplay.chord
        let tint = chord.map { NotePalette.color(for: $0.root) } ?? Color.white.opacity(0.14)

        HStack(spacing: 6) {
            if chord != nil {
                Text(IOSReadoutFormat.chordLabel(chord))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.28)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: chord?.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chord.map { "Live chord \($0.name)" } ?? "Listening for a chord")
    }
}

/// One explicit audio-state surface (D-10): an icon, a title, a short
/// explanation and an optional recovery action.
private struct IOSStatusBanner<Action: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

extension IOSStatusBanner where Action == EmptyView {
    init(title: String, message: String, systemImage: String, tint: Color) {
        self.init(title: title, message: message, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

/// Portrait Notes readout: the big tinted note capsule, the cents gauge and
/// the cents·Hz line. Owns the `display` read.
private struct IOSNotesTunerReadout: View {
    let state: AppState

    var body: some View {
        let display = state.display
        let note = display.note
        let color = note.map { NotePalette.color(for: $0.name) } ?? Color.white.opacity(0.14)

        VStack(spacing: 14) {
            Text("NOTE")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note?.name ?? "—")
                    .font(.system(size: 110, weight: .black))
                    .tracking(-3)
                if let note {
                    Text("\(note.octave)")
                        .font(.system(size: 40, weight: .bold))
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 44)
            .frame(height: 150)
            .background(Capsule().fill(color.opacity(0.25)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: note?.midiNote)

            TunerGauge(displayCents: note?.cents ?? 0, isActive: note != nil)
                .frame(height: 54)
                .padding(.top, 8)

            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(note.map { String(format: "%+.0f", $0.cents) } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("CENTS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
                Text("·")
                    .foregroundStyle(.tertiary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(display.frequency.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("HZ")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Portrait Chords readout: the big chord capsule and the confidence bar.
/// Owns the `chordDisplay` read.
private struct IOSChordsTunerReadout: View {
    let state: AppState

    var body: some View {
        let chord = state.chordDisplay.chord
        let color = chord.map { NotePalette.color(for: $0.root) } ?? Color.white.opacity(0.14)

        VStack(spacing: 14) {
            Text("CHORD")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(chord?.name ?? "—")
                .font(.system(size: 96, weight: .black))
                .tracking(-2)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(color)
                .padding(.horizontal, 38)
                .frame(height: 150)
                .background(Capsule().fill(color.opacity(0.25)))
                .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: chord?.name)

            VStack(spacing: 10) {
                HStack {
                    Text("CONFIDENCE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(chord.map { "\(Int(($0.confidence * 100).rounded()))%" } ?? "—")
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(color)
                            .frame(width: proxy.size.width * CGFloat(chord?.confidence ?? 0))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

/// A tiny segmented level bar shared by the compact meters.
/// (`InputLevelPanel` is the Mac's 4-row dot matrix; this is the single-row
/// bar both the portrait level card and any compact readout draw.)
private struct IOSCompactLevelMeter: View {
    let level: Float
    var barHeight: CGFloat = 4

    var body: some View {
        let normalized = IOSReadoutFormat.normalizedLevel(level)
        GeometryReader { proxy in
            let columns = max(2, Int(proxy.size.width / 9))
            HStack(spacing: 2) {
                ForEach(0..<columns, id: \.self) { column in
                    let fraction = Double(column) / Double(columns - 1)
                    let lit = column < Int((normalized * Double(columns)).rounded())
                    RoundedRectangle(cornerRadius: 1)
                        .fill(lit
                              ? (fraction < 0.69 ? Color.green : (fraction < 0.885 ? Color.yellow : Color.red))
                              : Color.white.opacity(0.10))
                }
            }
        }
        .frame(height: barHeight)
    }
}

/// Owns the level read, which lives in `display` in Notes mode and
/// `chordDisplay` in Chords mode.
/// Compact single-row level card (≈44pt): INPUT caption, one row of segments,
/// and the dB figure. Replaces the Mac's 4-row dot-matrix `InputLevelPanel` on
/// the portrait Listen screen. Still a leaf — it owns the level read.
private struct IOSInputLevelLeaf: View {
    let state: AppState
    let mode: DetectionMode

    var body: some View {
        let level = mode == .notes ? state.display.level : state.chordDisplay.level
        HStack(spacing: 12) {
            Text("INPUT")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            IOSCompactLevelMeter(level: level, barHeight: 20)
            Text(IOSReadoutFormat.decibelsText(level))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .monospacedDigit()
            Text("dB")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 14, fill: 0.035)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(IOSReadoutFormat.decibelsText(level)) decibels")
    }
}

/// Owns the history read (notes or chords).
/// The RECENT strip as a native horizontally scrolling row. The clear button
/// sits *outside* the scroll view at the trailing edge, so it stays reachable
/// no matter how many chips accumulate, and the chips never clip. Owns the
/// history read.
private struct IOSHistoryLeaf: View {
    let state: AppState
    let mode: DetectionMode

    var body: some View {
        switch mode {
        case .notes:
            historyRow(
                entries: state.noteHistory,
                pinnedID: state.pinnedNoteHistoryID,
                label: { "\($0.note.name)\($0.note.octave)" },
                tint: { NotePalette.color(for: $0.note.name) },
                onSelect: { state.pinnedNoteHistoryID = $0 },
                onClear: { state.clearNoteHistory() }
            )
        case .chords:
            historyRow(
                entries: state.chordHistory,
                pinnedID: state.pinnedChordHistoryID,
                label: { $0.match.name },
                tint: { NotePalette.color(for: $0.match.root) },
                onSelect: { state.pinnedChordHistoryID = $0 },
                onClear: { state.clearChordHistory() }
            )
        }
    }

    private func historyRow<Entry>(
        entries: [Entry],
        pinnedID: UUID?,
        label: @escaping (Entry) -> String,
        tint: @escaping (Entry) -> Color,
        onSelect: @escaping (UUID?) -> Void,
        onClear: @escaping () -> Void
    ) -> some View where Entry: Identifiable, Entry.ID == UUID {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        let isPinned = entry.id == pinnedID
                        Button {
                            onSelect(isPinned ? nil : entry.id)
                        } label: {
                            Text(label(entry))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(tint(entry), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(isPinned ? 0.9 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            if !entries.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .accessibilityLabel("Clear history")
            }
        }
        .frame(height: 44)
    }
}

/// The landscape neck: the existing listening board + `DetectionBoardAdapter`,
/// fitted to whatever width remains.
private struct IOSBoardLeaf: View {
    let state: AppState

    var body: some View {
        FretboardView(
            mode: state.detectionMode,
            note: state.displayedNote,
            positions: state.displayedPositions,
            chord: state.displayedChord,
            flipped: state.isFretboardFlipped
        )
    }
}
