import SwiftUI

/// Pentatonic scales — five boxes with guided practice.
struct PentatonicModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: PentatonicModuleModel?
    @State private var showsFullNeck = false
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
            if model == nil { model = state.makePentatonicModuleModel() }
            state.refreshSamplePlaybackReadiness()
        }
        .onDisappear { model?.stop() }
    }

    private func content(_ model: PentatonicModuleModel) -> some View {
        let dots = labelMode == .notes ? model.dots.showingNoteNames(in: Tunings.standard) : model.dots
        return ModuleLayout(module: .pentatonic, state: state) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                StandardTuningNotice(tuning: state.tuning, what: "These boxes")
                controls(model)
            }
        } stage: {
            VStack(alignment: .trailing, spacing: 8) {
                FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: model.highestFret)
                FretboardBoardView(
                    dots: dots,
                    frets: showsFullNeck ? 22 : model.highestFret,
                    tuning: Tunings.standard,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
                .moduleLiveNoteGlow(state: state, dots: dots, frets: showsFullNeck ? 22 : model.highestFret, tuning: Tunings.standard, flipped: state.isFretboardFlipped)
                .frame(minHeight: 260)
            }
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: PentatonicModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PitchClassPicker(title: "ROOT", selection: model.rootPitchClass, onSelect: model.selectRoot)
                .moduleNotesCard()

            HStack(spacing: 16) {
                Picker("Quality", selection: Binding(
                    get: { model.quality },
                    set: { model.selectQuality($0) }
                )) {
                    Text("Minor").tag(PentatonicQuality.minorPentatonic)
                    Text("Major").tag(PentatonicQuality.majorPentatonic)
                }
                .fixedSize()

                Picker("Show", selection: Binding(
                    get: { model.displayMode },
                    set: { model.selectDisplayMode($0) }
                )) {
                    Text("One box").tag(PentatonicModuleModel.DisplayMode.single)
                    Text("Pair").tag(PentatonicModuleModel.DisplayMode.pair)
                    Text("Path").tag(PentatonicModuleModel.DisplayMode.path)
                }
                .fixedSize()

                Picker("Position", selection: Binding(
                    get: { model.position },
                    set: { model.selectPosition($0) }
                )) {
                    // 0-based internally, 1-based on screen.
                    ForEach(0...4, id: \.self) { Text("Box \($0 + 1)").tag($0) }
                }
                .fixedSize()

                FretboardLabelPicker(selection: $labelMode)

                guidedControls(model)
            }
            .moduleOptionsCard()
        }
    }

    private func guidedControls(_ model: PentatonicModuleModel) -> some View {
        HStack(spacing: 12) {
            if model.guidedSnapshot.status == .idle {
                Button { model.startGuided() } label: { Label("Practise", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .tint(NotePalette.accent)
                    .disabled(model.box.isEmpty)
            } else {
                Button("Stop") { model.stopGuided() }
                Button { _ = model.slower() } label: { Image(systemName: "tortoise") }
                Text("\(model.guidedSnapshot.tempoBpm) bpm")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { _ = model.faster() } label: { Image(systemName: "hare") }

                if let beat = model.guidedSnapshot.countInBeat {
                    Text("Count in… \(beat)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(NotePalette.accent)
                } else if let index = model.guidedSnapshot.currentIndex {
                    Text("\(index + 1) / \(model.guidedSnapshot.total)")
                        .font(.callout.monospacedDigit())
                }
            }
        }
    }


    private func readout(_ model: PentatonicModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(label: "Scale",
                           value: "\(model.rootPitchClass.name()) \(model.quality == .minorPentatonic ? "minor" : "major") pentatonic",
                           tint: NotePalette.color(for: .root))
                ModuleStat(label: "Box", value: "\(model.focusPosition + 1) of 5")
                ModuleStat(label: "Notes", value: "\(model.box.count)")
            }

            // The live practice readout: what to play now, with what finger,
            // and what is coming next.
            if let step = model.currentStep {
                HStack(alignment: .top, spacing: 28) {
                    ModuleStat(label: "Play", value: "\(step.pitchClass.name())  fret \(step.fret)",
                               tint: NotePalette.color(for: .pentatonic))
                    ModuleStat(label: "String", value: Tunings.standard.stringNames[step.string])
                    ModuleStat(label: "Finger", value: Self.fingerName(step.finger))
                    ModuleStat(label: "Degree", value: step.degree.isEmpty ? "—" : step.degree)
                    if let next = model.nextStep {
                        ModuleStat(label: "Next", value: "\(next.pitchClass.name())  fret \(next.fret)")
                    }
                }
            }

            ModuleProse(paragraphs: prose(model))
        }
    }

    private static func fingerName(_ finger: FrettingFinger) -> String {
        switch finger {
        case .open: "Open"
        case .index: "Index"
        case .middle: "Middle"
        case .ring: "Ring"
        case .little: "Little"
        }
    }

    private func prose(_ model: PentatonicModuleModel) -> [String] {
        var paragraphs = [
            "Five notes instead of seven. Dropping the two that clash is what makes the pentatonic so forgiving — almost anything you play inside the box sits well against the chord, which is why it is the first scale most players solo with."
        ]
        switch model.displayMode {
        case .single:
            paragraphs.append("Box \(model.focusPosition + 1) of five. Each box is two notes per string, and together the five cover the whole neck.")
        case .pair:
            paragraphs.append("Two boxes side by side. The greyed notes belong to the neighbouring box — see how the two overlap, because that shared edge is how you move between them without stopping.")
        case .path:
            paragraphs.append("Three boxes, with box \(model.focusPosition + 1) in the middle. Seeing where a box came from and where it goes is what turns five memorised shapes into one connected neck.")
        }
        return paragraphs
    }
}

/// Shown by modules whose shapes are fixed fret patterns, when the globally
/// selected tuning is not standard.
///
/// Those shapes do not transpose — they detune — so the honest thing is to say
/// they will not sound as written rather than to draw something quietly wrong.
struct StandardTuningNotice: View {
    let tuning: Tuning
    let what: String

    var body: some View {
        if tuning.id != .standard {
            Label(
                "\(what) are standard-tuning forms. You have \(tuning.name) selected, so they will not sound as written.",
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
}
