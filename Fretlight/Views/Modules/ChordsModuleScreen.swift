import SwiftUI

/// Major, minor and power chords — movable shapes read as degrees.
struct ChordsModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: ChordsModuleModel?

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
        ModuleLayout(module: .chords) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                tuningNotice
                controls(model)
            }
        } stage: {
            FretboardBoardView(
                dots: model.dots,
                frets: model.highestFret,
                tuning: Tunings.standard,
                flipped: state.isFretboardFlipped,
                pulses: model.pulses
            )
            .frame(minHeight: 260)
        } readout: {
            readout(model)
        }
    }

    /// These shapes are fixed fret patterns, so they only mean anything in
    /// standard tuning. Saying so is better than drawing a shape that is
    /// quietly wrong for the tuning the player has selected globally.
    @ViewBuilder
    private var tuningNotice: some View {
        if state.tuning.id != .standard {
            Label(
                "These shapes are standard-tuning forms. You have \(state.tuning.name) selected, so they will not sound as written.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func controls(_ model: ChordsModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ROOT")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(0..<12, id: \.self) { value in
                        rootButton(model, pitchClass: PitchClass(value))
                    }
                }
            }

            HStack(spacing: 12) {
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
            }

            HStack(spacing: 12) {
                Button { model.movePosition(by: -1) } label: { Label("Lower", systemImage: "chevron.left") }
                    .disabled(model.voicings.count < 2)
                Button { model.movePosition(by: 1) } label: { Label("Higher", systemImage: "chevron.right") }
                    .disabled(model.voicings.count < 2)
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
        }
    }

    private func rootButton(_ model: ChordsModuleModel, pitchClass: PitchClass) -> some View {
        let isActive = model.rootPitchClass == pitchClass
        let color = NotePalette.color(for: pitchClass)
        return Button {
            model.selectRoot(pitchClass)
        } label: {
            Text(pitchClass.name())
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isActive ? color : color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(isActive ? Color.black : color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pitchClass.name())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
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
