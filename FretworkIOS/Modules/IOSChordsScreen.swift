import SwiftUI

/// The Chords module on iOS.
///
/// Portrait reuses the existing Mac `ChordsModuleScreen` verbatim as the
/// fallback (D-18) — the model, shapes and playback are all real, wired by
/// `AppState`. Landscape is the M2 arrangement (D-20/D-22), rendered by the
/// shared `IOSModuleLandscapeScaffold`: a centred neck with fret numbers on
/// its top edge, translucent ‹ › arrows in the band just below the low E at
/// the neck's bottom corners, a drawer handle between them, and a slide-up
/// drawer holding the root/family/chord pickers, Strum/Stop and the
/// explanation.
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

    private var subtitle: String {
        IOSModuleLandscapeFormat.chordsPositionSubtitle(
            positionLabel: model.positionLabel,
            positionIndex: model.positionIndex,
            voicingCount: model.voicings.count
        )
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
        IOSModuleLandscapeScaffold(
            title: IOSModuleScreenTitle.title(for: .chords),
            subtitle: subtitle,
            tuning: state.tuning,
            isFixedShapeModule: true,
            state: state,
            neck: {
                FretboardBoardView(
                    dots: model.dots,
                    frets: model.highestFret,
                    tuning: Tunings.standard,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
            },
            leadingAction: .step(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous position",
                disabled: isPrevDisabled,
                action: { withAnimation(FretworkMotion.gravity) { model.movePosition(by: -1) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Next position",
                disabled: isNextDisabled,
                action: { withAnimation(FretworkMotion.gravity) { model.movePosition(by: 1) } }
            ),
            drawerTitle: "Chord & key",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSChordsDrawer(state: state, model: model)
            },
            bandMode: .normal,
            guidedRunStepText: "",
            onStopGuidedRun: {}
        )
        .onDisappear { model.stop() }
    }
}

// MARK: - Drawer

private struct IOSChordsDrawer: View {
    let state: AppState
    let model: ChordsModuleModel

    private var positionOfCount: String {
        guard let index = model.positionIndex else { return "—" }
        return "\(index + 1) of \(model.voicings.count)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PitchClassPicker(
                    title: "Root",
                    selection: model.rootPitchClass,
                    onSelect: model.selectRoot
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Chord")
                        .font(.headline)
                    VStack(spacing: 12) {
                        LabeledContent("Family") {
                            familyPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        LabeledContent("Chord") {
                            formulaPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                Text("\(model.symbol) · \(model.currentVoicing?.shape ?? "—") · \(positionOfCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                IOSModulePlaybackNotice(state: state)

                HStack(spacing: 12) {
                    Button {
                        model.strum()
                    } label: {
                        Label("Strum", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(NotePalette.accent)
                    .disabled(model.currentVoicing == nil || !state.isSamplePlaybackReady)

                    Button("Stop") { model.stop() }
                        .buttonStyle(.glass)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                    Text(model.formula.description)
                    Text("The dots are labelled by degree — \(model.formula.degrees.joined(separator: ", ")) — rather than by note name, so the same shape reads the same wherever you move it.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .tint(NotePalette.accent)
    }

    private var familyPicker: some View {
        Picker("Family", selection: Binding(
            get: { model.family },
            set: { model.selectFamily($0) }
        )) {
            ForEach(ChordsModuleModel.families, id: \.self) { family in
                Text(ChordsModuleModel.label(for: family)).tag(family)
            }
        }
        .pickerStyle(.menu)
    }

    private var formulaPicker: some View {
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
        .pickerStyle(.menu)
    }
}
