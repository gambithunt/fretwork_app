import SwiftUI

/// Triads — shapes, inversions, double-stops, and diatonic paths along one
/// string set.
struct TriadsModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: TriadsModuleModel?
    @State private var labelMode: FretboardLabelMode = .degrees

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = state.makeTriadsModuleModel() }
            state.refreshSamplePlaybackReadiness()
            #if DEBUG
            if ModuleRunSnapshot.forceTriadsPathMode || ModuleRunSnapshot.forcedRun != .idle {
                model?.debugForceRun(ModuleRunSnapshot.forcedRun)
            }
            #endif
        }
        .onChange(of: state.tuning) { _, tuning in model?.retune(to: tuning) }
        .onDisappear { model?.stopEverything() }
    }

    private func content(_ model: TriadsModuleModel) -> some View {
        let dots = labelMode == .notes ? model.dots.showingNoteNames(in: model.tuning) : model.dots
        return ModuleLayout(module: .triads, state: state) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                Self.controls(model, labelMode: $labelMode)
            }
        } stage: {
            // Shapes mode moves along the neck with Lower/Higher; Paths
            // walks the diatonic path with Play/Loop instead, so the edge
            // nav only appears in the mode it actually acts on.
            FretboardEdgeNav(
                onPrevious: model.isPathMode ? nil : { model.movePosition(by: -1) },
                onNext: model.isPathMode ? nil : { model.movePosition(by: 1) }
            ) {
                FretboardBoardView(
                    dots: dots,
                    frets: model.highestFret,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
                .moduleLiveNoteGlow(state: state, dots: dots, frets: model.highestFret, tuning: model.tuning, flipped: state.isFretboardFlipped)
                .frame(minHeight: 260)
            }
        } readout: {
            readout(model)
        }
    }

    static func controls(_ model: TriadsModuleModel, labelMode: Binding<FretboardLabelMode>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PitchClassPicker(
                title: model.isPathMode ? "KEY" : "ROOT",
                selection: model.isPathMode ? model.pathKeyRoot : model.rootPitchClass,
                onSelect: model.selectRoot
            )
            .moduleNotesCard()

            ModuleControlCard {
                Picker("Exercise", selection: Binding(
                    get: { model.isPathMode },
                    set: { model.setPathMode($0) }
                )) {
                    Text("Shapes").tag(false)
                    Text("Paths").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .tint(NotePalette.accent)
                .moduleControlCell(caption: "EXERCISE")

                FretboardLabelPicker(selection: labelMode)
                .moduleMenuPicker()
                    .moduleControlCell(caption: "LABELS")

                if model.isPathMode {
                    pathCells(model)
                } else {
                    shapeCells(model)
                }
            }
        }
    }

    @ViewBuilder
    private static func shapeCells(_ model: TriadsModuleModel) -> some View {
        Picker("Triad", selection: Binding(
            get: { model.view == .doubleStops ? "doubleStops" : model.triad.short },
            set: { value in
                if value == "doubleStops" {
                    model.selectDoubleStop(model.doubleStop)
                } else if let triad = Triads.all.first(where: { $0.short == value }) {
                    model.selectTriad(triad)
                }
            }
        )) {
            ForEach(Triads.all, id: \.short) { triad in
                Text(triad.name).tag(triad.short)
            }
            Text("Double stops").tag("doubleStops")
        }
        .labelsHidden()
        .fixedSize()
        .moduleMenuPicker()
        .moduleControlCell(caption: "TRIAD")

        if model.view == .doubleStops {
            Picker("Pair", selection: Binding(
                get: { model.doubleStop.id },
                set: { id in
                    if let pair = DoubleStops.all.first(where: { $0.id == id }) {
                        model.selectDoubleStop(pair)
                    }
                }
            )) {
                ForEach(DoubleStops.all, id: \.id) { pair in
                    Text(pair.label).tag(pair.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            .moduleMenuPicker()
            .moduleControlCell(caption: "PAIR")
        } else {
            Picker("Inversion", selection: Binding(
                get: { model.selectedInversion ?? TriadsModuleModel.inversionOrder[0] },
                set: { model.selectInversion($0) }
            )) {
                ForEach(model.availableInversions, id: \.self) { inversion in
                    Text(inversion).tag(inversion)
                }
            }
            .labelsHidden()
            .fixedSize()
            .moduleMenuPicker()
            .disabled(model.availableInversions.count < 2)
            .moduleControlCell(caption: "INVERSION")
        }

        ModulePrimaryAction(
            title: "Play shape",
            disabled: model.activeVoicing == nil,
            action: { model.playVoicing() },
            stopAction: { model.stop() }
        )
        .moduleControlCell(caption: "PLAY", alignment: .trailing)
    }

    @ViewBuilder
    private static func pathCells(_ model: TriadsModuleModel) -> some View {
        Picker("String set", selection: Binding(
            get: { model.pathStringSet },
            set: { model.selectPathStringSet($0) }
        )) {
            ForEach(TriadPaths.stringSets, id: \.self) { set in
                Text(set.rawValue).tag(set)
            }
        }
        .labelsHidden()
        .fixedSize()
        .moduleMenuPicker()
        .moduleControlCell(caption: "STRING SET")

        Picker("Key", selection: Binding(
            get: { model.pathIsMajor },
            set: { model.setPathMajor($0) }
        )) {
            Text("Major").tag(true)
            Text("Minor").tag(false)
        }
        .labelsHidden()
        .fixedSize()
        .moduleMenuPicker()
        .moduleControlCell(caption: "KEY")

        ModuleSecondaryAction(
            title: "Loop",
            systemImage: "repeat",
            disabled: model.pathSteps.isEmpty,
            action: { model.startProgression(loop: true) }
        )
        .moduleControlCell(caption: "LOOP")

        HStack(spacing: 8) {
            Button { _ = model.slower() } label: { Image(systemName: "tortoise") }
                .moduleSecondaryButton()
                .accessibilityLabel("Slower")
            Text("\(model.tempoBpm) bpm")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button { _ = model.faster() } label: { Image(systemName: "hare") }
                .moduleSecondaryButton()
                .accessibilityLabel("Faster")
            ModuleRunProgress(
                index: model.progressionSnapshot.currentIndex,
                total: model.pathSteps.count
            )
        }
        .moduleControlCell(caption: "TEMPO")

        ModulePrimaryAction(
            title: "Play path",
            disabled: model.pathSteps.isEmpty,
            countInBeat: model.progressionSnapshot.countInBeat,
            action: { model.startProgression(loop: false) },
            stopAction: { model.stopEverything() }
        )
        .moduleControlCell(caption: "PLAY", alignment: .trailing)
    }


    private func readout(_ model: TriadsModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                if model.isPathMode {
                    ModuleStat(label: "Chord",
                               value: model.currentPathStep?.chord.name ?? "—",
                               tint: NotePalette.color(for: .root))
                    ModuleStat(label: "Degree",
                               value: model.currentPathStep?.chord.roman ?? "—")
                    ModuleStat(label: "Step",
                               value: model.pathSteps.isEmpty ? "—" : "\(model.pathStep + 1) / \(model.pathSteps.count)")
                    ModuleStat(label: "Strings", value: model.pathStringSet.rawValue)
                } else {
                    ModuleStat(label: "Chord",
                               value: "\(model.rootPitchClass.name())\(model.view == .doubleStops ? "" : model.triad.short == "maj" ? "" : model.triad.short)",
                               tint: NotePalette.color(for: .root))
                    ModuleStat(label: model.view == .doubleStops ? "Pair" : "Inversion",
                               value: model.view == .doubleStops ? model.doubleStop.label : (model.selectedInversion ?? "—"))
                    ModuleStat(label: "Position",
                               value: model.voicings.isEmpty ? "—" : "\(model.position + 1) / \(model.voicings.count)")
                }
            }

            degreeKey(model)
            ModuleProse(paragraphs: prose(model))
        }
    }

    /// The colour key, because the dots are coloured by role here rather than
    /// by pitch and that swap needs saying.
    private func degreeKey(_ model: TriadsModuleModel) -> some View {
        HStack(spacing: 14) {
            ForEach(Array((model.activeVoicing?.tones ?? []).enumerated()), id: \.offset) { _, tone in
                HStack(spacing: 5) {
                    Circle()
                        .fill(NotePalette.color(for: TriadsModuleModel.role(forDegree: tone.degree)))
                        .frame(width: 10, height: 10)
                    Text("\(tone.degree) · \(tone.position.pitchClass.name())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func prose(_ model: TriadsModuleModel) -> [String] {
        if model.isPathMode {
            return [
                "Every chord in the key, voiced on one set of three adjacent strings. The harmony moves; your hand does not leave the \(model.pathStringSet.rawValue) strings. That constraint is the exercise — it is how you learn to comp behind someone without hunting for shapes.",
                "The dots are coloured by what each note is doing — root, third, fifth — not by which note it is. The third is the one to watch: it alone decides whether a chord sounds major or minor."
            ]
        }
        if model.view == .doubleStops {
            return [
                model.doubleStop.description,
                "Two notes instead of three. Drop the fifth and a triad still carries its character, because the third is doing the work — which is why double stops sit so well in a busy arrangement."
            ]
        }
        return [
            model.triad.feel,
            "Three notes stacked in thirds: \(model.triad.degrees.joined(separator: ", ")). Every chord you play is this, thickened or rearranged. The dots are coloured by role rather than by pitch, so you can see the shape as degrees rather than as letters.",
            "An inversion is the same three notes with a different one in the bass. It is not a new chord — it is the same harmony sitting somewhere else under your hand."
        ]
    }
}
