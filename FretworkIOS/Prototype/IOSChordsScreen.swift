import SwiftUI

/// The Chords module on iOS.
///
/// Portrait reuses the existing Mac `ChordsModuleScreen` verbatim as the
/// fallback (D-18) — the model, shapes and playback are all real, wired by
/// `AppState`. Landscape is the M2 arrangement (D-20/D-22): a centred neck
/// with fret numbers on its top edge, translucent ‹ › arrows in the band just
/// below the low E at the neck's bottom corners, a drawer handle between
/// them, and a slide-up drawer holding the root/family/chord pickers,
/// Strum/Stop and the explanation.
struct IOSChordsScreen: View {
    @Bindable var state: AppState

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var landscapeModel: ChordsModuleModel?

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                if let model = landscapeModel {
                    IOSChordsLandscape(state: state, model: model)
                } else {
                    Color.clear
                        .task {
                            if landscapeModel == nil {
                                landscapeModel = state.makeChordsModuleModel()
                                state.refreshSamplePlaybackReadiness()
                            }
                        }
                }
            } else {
                ChordsModuleScreen(state: state)
            }
        }
        .background(NotePalette.backdrop)
    }
}

// MARK: - Landscape (M2)

private struct IOSChordsLandscape: View {
    let state: AppState
    let model: ChordsModuleModel
    @State private var showsDrawer = false

    private var positionLabel: String {
        guard let index = model.positionIndex else { return model.positionLabel }
        return "\(model.positionLabel) · \(index + 1) of \(model.voicings.count)"
    }

    private var isPrevDisabled: Bool {
        guard let index = model.positionIndex, model.voicings.count > 1 else { return true }
        return index == 0
    }

    private var isNextDisabled: Bool {
        guard let index = model.positionIndex, model.voicings.count > 1 else { return true }
        return index == model.voicings.count - 1
    }

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
            IOSChordsDrawer(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(NotePalette.backdrop)
        }
        .onDisappear { model.stop() }
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            Text(positionLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            IOSCompactStandardTuningNotice(tuning: state.tuning)
            IOSModuleLiveNoteLeaf(state: state, enabled: state.showsLiveNoteOnModules)
        }
    }

    private var neck: some View {
        FretboardBoardView(
            dots: model.dots,
            frets: model.highestFret,
            tuning: Tunings.standard,
            flipped: state.isFretboardFlipped,
            pulses: model.pulses
        )
    }

    private var bottomBand: some View {
        HStack {
            positionButton(systemImage: "chevron.left", disabled: isPrevDisabled) {
                withAnimation(FretworkMotion.gravity) { model.movePosition(by: -1) }
            }
            Spacer()
            drawerHandle
            Spacer()
            positionButton(systemImage: "chevron.right", disabled: isNextDisabled) {
                withAnimation(FretworkMotion.gravity) { model.movePosition(by: 1) }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
    }

    private func positionButton(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(disabled ? Color.white.opacity(0.3) : NotePalette.accent)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .disabled(disabled)
    }

    private var drawerHandle: some View {
        Button {
            showsDrawer = true
        } label: {
            VStack(spacing: 4) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 36, height: 5)
                Text("Chord & key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 120, height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Drawer

private struct IOSChordsDrawer: View {
    let model: ChordsModuleModel

    private var positionOfCount: String {
        guard let index = model.positionIndex else { return "—" }
        return "\(index + 1) of \(model.voicings.count)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PitchClassPicker(
                    title: "ROOT",
                    selection: model.rootPitchClass,
                    onSelect: model.selectRoot
                )

                HStack(spacing: 12) {
                    Picker("Family", selection: Binding(
                        get: { model.family },
                        set: { model.selectFamily($0) }
                    )) {
                        ForEach(ChordsModuleModel.families, id: \.self) { family in
                            Text(ChordsModuleModel.label(for: family)).tag(family)
                        }
                    }

                    Picker("Chord", selection: Binding(
                        get: { model.formula.id },
                        set: { id in
                            if let formula = ChordFormulas.formula(id: id) {
                                model.selectFormula(formula)
                            }
                        }
                    )) {
                        ForEach(model.formulasInFamily, id: \.id) { formula in
                            Text(formula.label.isEmpty ? "Major" : formula.label).tag(formula.id)
                        }
                    }
                }

                Text("\(model.symbol) · \(model.currentVoicing?.shape ?? "—") · \(positionOfCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        model.strum()
                    } label: {
                        Label("Strum", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NotePalette.accent)
                    .disabled(model.currentVoicing == nil)

                    Button("Stop") { model.stop() }
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.formula.description)
                    Text("The dots are labelled by degree — \(model.formula.degrees.joined(separator: ", ")) — rather than by note name, so the same shape reads the same wherever you move it.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(NotePalette.backdrop)
        .preferredColorScheme(.dark)
        .tint(NotePalette.accent)
    }
}

// MARK: - Leaves

/// The 008 live-note capsule, rebuilt here as a leaf because the Mac's
/// `ModuleLiveNoteReadout` is private to `ModuleLayout`. Reads `display` only
/// while the feature is on, and owns that read so the rest of the top bar
/// never sees audio-rate invalidations.
private struct IOSModuleLiveNoteLeaf: View {
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
private struct IOSCompactStandardTuningNotice: View {
    let tuning: Tuning

    var body: some View {
        if tuning.id != .standard {
            Label("Standard tuning shapes", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.12), in: Capsule())
        }
    }
}
