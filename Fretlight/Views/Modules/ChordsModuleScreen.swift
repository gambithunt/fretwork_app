import SwiftUI

/// Major, minor and power chords — movable shapes read as degrees.
struct ChordsModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: ChordsModuleModel?
    @State private var showsFullNeck = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = state.makeChordsModuleModel() }
            state.refreshSamplePlaybackReadiness()
        }
        .onDisappear { model?.stop() }
    }

    private func content(_ model: ChordsModuleModel) -> some View {
        ModuleLayout(module: .chords, state: state) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                StandardTuningNotice(tuning: state.tuning, what: "These shapes")
                controls(model)
            }
        } stage: {
            VStack(alignment: .trailing, spacing: 8) {
                FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: model.highestFret)
                FretboardEdgeNav(
                    onPrevious: model.voicings.count < 2 ? nil : { model.movePosition(by: -1) },
                    onNext: model.voicings.count < 2 ? nil : { model.movePosition(by: 1) }
                ) {
                    FretboardBoardView(
                        dots: model.dots,
                        frets: showsFullNeck ? 22 : model.highestFret,
                        tuning: Tunings.standard,
                        flipped: state.isFretboardFlipped,
                        pulses: model.pulses
                    )
                    .frame(minHeight: 260)
                }
            }
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: ChordsModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PitchClassPicker(title: "ROOT", selection: model.rootPitchClass, onSelect: model.selectRoot)
                .moduleNotesCard()

            HStack(spacing: 16) {
                Picker("Family", selection: Binding(
                    get: { model.family },
                    set: { model.selectFamily($0) }
                )) {
                    ForEach(ChordsModuleModel.families, id: \.self) { family in
                        Text(ChordsModuleModel.label(for: family)).tag(family)
                    }
                }
                .fixedSize()

                Picker("Chord", selection: Binding(
                    get: { model.formula.id },
                    set: { id in
                        if let formula = ChordFormulas.formula(id: id) { model.selectFormula(formula) }
                    }
                )) {
                    ForEach(model.formulasInFamily, id: \.id) { formula in
                        Text(formula.label.isEmpty ? "Major" : formula.label).tag(formula.id)
                    }
                }
                .fixedSize()

                Button {
                    model.strum()
                } label: {
                    Label("Strum", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(NotePalette.accent)
                .disabled(model.currentVoicing == nil)
                Button("Stop") { model.stop() }
            }
            .moduleOptionsCard()
        }
    }

    private func readout(_ model: ChordsModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(label: "Chord", value: model.symbol, tint: NotePalette.color(for: .root))
                ModuleStat(label: "Shape", value: model.currentVoicing?.shape ?? "—")
                ModuleStat(label: "Position", value: model.positionLabel)
                if let index = model.positionIndex {
                    ModuleStat(label: "Of", value: "\(index + 1) / \(model.voicings.count)")
                }
            }
            mutedStrings(model)
            ModuleProse(paragraphs: prose(model))
        }
    }

    /// Muted strings are part of the shape. A diagram that leaves them out
    /// teaches a chord you cannot actually strum.
    @ViewBuilder
    private func mutedStrings(_ model: ChordsModuleModel) -> some View {
        let muted = model.mutedStrings
        if !muted.isEmpty {
            Label(
                "Don't play: \(muted.map { Tunings.standard.stringNames[$0] }.joined(separator: ", "))",
                systemImage: "xmark.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func prose(_ model: ChordsModuleModel) -> [String] {
        var paragraphs = [model.formula.description]
        paragraphs.append(
            "The dots are labelled by degree — \(model.formula.degrees.joined(separator: ", ")) — rather than by note name, so the same shape reads the same wherever you move it. That is what makes it movable: slide the form and every degree keeps its job, only the root changes."
        )
        if let voicing = model.currentVoicing, voicing.isOpen {
            paragraphs.append("This is an open shape: it uses unfretted strings, so it cannot be slid up the neck the way a barred form can.")
        }
        return paragraphs
    }
}
