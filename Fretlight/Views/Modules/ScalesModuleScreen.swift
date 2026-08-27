import SwiftUI

/// Scales — one-octave major and natural-minor shapes with guided practice.
struct ScalesModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: ScalesModuleModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = state.makeScalesModuleModel() }
            state.refreshSamplePlaybackReadiness()
        }
        .onChange(of: state.tuning) { _, tuning in model?.retune(to: tuning) }
        .onDisappear { model?.stopGuided() }
    }

    private func content(_ model: ScalesModuleModel) -> some View {
        ModuleLayout(module: .scales) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                controls(model)
            }
        } stage: {
            FretboardBoardView(
                dots: model.dots,
                frets: model.highestFret,
                tuning: model.tuning,
                flipped: state.isFretboardFlipped
            )
            .frame(minHeight: 260)
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: ScalesModuleModel) -> some View {
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
                Picker("Scale", selection: Binding(
                    get: { model.quality },
                    set: { model.selectQuality($0) }
                )) {
                    Text("Major").tag(OneOctaveScaleQuality.major)
                    Text("Natural minor").tag(OneOctaveScaleQuality.naturalMinor)
                }
                .fixedSize()

                Picker("Labels", selection: Binding(
                    get: { model.labelMode },
                    set: { model.selectLabelMode($0) }
                )) {
                    Text("Notes").tag(ScalesModuleModel.LabelMode.notes)
                    Text("Degrees").tag(ScalesModuleModel.LabelMode.degrees)
                }
                .fixedSize()

                Picker("Direction", selection: Binding(
                    get: { model.direction },
                    set: { model.selectDirection($0) }
                )) {
                    Text("Ascending").tag(ScalesModuleModel.Direction.ascending)
                    Text("Up and down").tag(ScalesModuleModel.Direction.upDown)
                }
                .fixedSize()
            }

            HStack(spacing: 12) {
                if model.guidedSnapshot.status == .idle {
                    Button { model.startGuided() } label: { Label("Practise", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .tint(NotePalette.accent)
                        .disabled(model.sequence.isEmpty)
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
    }

    private func rootButton(_ model: ScalesModuleModel, pitchClass: PitchClass) -> some View {
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

    private func readout(_ model: ScalesModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(label: "Scale", value: model.scaleName, tint: NotePalette.color(for: .root))
                ModuleStat(label: "Notes", value: "\(model.steps.count)")
                ModuleStat(label: "Run", value: "\(model.sequence.count) notes")
            }

            if let step = model.currentStep {
                HStack(alignment: .top, spacing: 28) {
                    ModuleStat(label: "Play", value: "\(step.pitchClass.name())  fret \(step.fret)",
                               tint: NotePalette.color(for: step.pitchClass))
                    ModuleStat(label: "String", value: model.tuning.stringNames[step.string])
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

    private func prose(_ model: ScalesModuleModel) -> [String] {
        var paragraphs = [
            "The \(model.scaleName) scale, one octave from its root. Eight notes: seven degrees and then the root again on top, which is what makes it sound finished rather than stopped."
        ]
        paragraphs.append(
            model.quality == .major
                ? "Major is the reference every other scale is described against — its degrees are the plain numbers, and the minor scales are written as flattened versions of them."
                : "Natural minor is the major scale with its 3rd, 6th and 7th flattened. Same notes as its relative major, started three semitones lower — which is why the shapes feel familiar before they sound familiar."
        )
        if model.labelMode == .degrees {
            paragraphs.append("Labelled by degree, so the shape reads the same in every key. Switch to notes when you want to learn where you are on the neck rather than what the shape is doing.")
        } else {
            paragraphs.append("Labelled by note. Switch to degrees when you want the shape to read the same in every key.")
        }
        return paragraphs
    }
}
