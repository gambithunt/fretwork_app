import SwiftUI

/// Note association — chord tones, pentatonic and scale layered on one neck.
struct NoteAssociationModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: NoteAssociationModuleModel?
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
            if model == nil { model = state.makeNoteAssociationModuleModel() }
            state.refreshSamplePlaybackReadiness()
        }
        .onChange(of: state.tuning) { _, tuning in model?.retune(to: tuning) }
        .onDisappear { model?.stopEverything() }
    }

    private func content(_ model: NoteAssociationModuleModel) -> some View {
        ModuleLayout(module: .noteAssociation, state: state) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                controls(model)
            }
        } stage: {
            VStack(alignment: .trailing, spacing: 8) {
                FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: model.highestFret)
                FretboardBoardView(
                    dots: model.dots,
                    frets: showsFullNeck ? 22 : model.highestFret,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
                .frame(minHeight: 260)
            }
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: NoteAssociationModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PitchClassPicker(title: "KEY", selection: model.keyRoot, onSelect: model.selectKeyRoot)
                .moduleNotesCard()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Mode", selection: Binding(
                        get: { model.isMajor },
                        set: { model.selectMajor($0) }
                    )) {
                        Text("Major").tag(true)
                        Text("Minor").tag(false)
                    }
                    .fixedSize()

                    Picker("Labels", selection: Binding(
                        get: { model.labelMode },
                        set: { model.setLabelMode($0) }
                    )) {
                        Text("Notes").tag(NoteAssociationModuleModel.LabelMode.notes)
                        Text("Degrees").tag(NoteAssociationModuleModel.LabelMode.degrees)
                    }
                    .fixedSize()
                }

                // The layer switches. Seeing the scale alone, or the chord
                // tones alone, is a different exercise from seeing all three
                // at once.
                HStack(spacing: 16) {
                    Toggle("Chord tones", isOn: Binding(
                        get: { model.showsChordTones },
                        set: { model.setLayer(chordTones: $0) }
                    ))
                    Toggle("Pentatonic", isOn: Binding(
                        get: { model.showsPentatonic },
                        set: { model.setLayer(pentatonic: $0) }
                    ))
                    Toggle("Rest of scale", isOn: Binding(
                        get: { model.showsScale },
                        set: { model.setLayer(scale: $0) }
                    ))
                }
                .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 6) {
                    Text("CHORD")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    ChipPicker(
                        values: Array(model.chords.indices),
                        selection: model.focusedDegree,
                        tint: { _ in NotePalette.accent },
                        onSelect: model.selectDegree,
                        isEmphasized: { model.playingDegree == $0 },
                        accessibilityLabel: { "\(model.chords[$0].roman), \(model.chords[$0].name)" }
                    ) { index, isActive in
                        VStack(spacing: 2) {
                            Text(model.chords[index].roman)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(isActive ? .black : .primary)
                            Text(model.chords[index].name)
                                .font(.caption2)
                                .foregroundStyle(isActive ? .black.opacity(0.65) : .secondary)
                        }
                    }
                }

                progressionControls(model)
            }
            .moduleOptionsCard()
        }
    }

    private func progressionControls(_ model: NoteAssociationModuleModel) -> some View {
        HStack(spacing: 12) {
            Picker("Progression", selection: Binding(
                get: { model.progressionID },
                set: { model.selectProgression($0) }
            )) {
                ForEach(model.progressions, id: \.id) { progression in
                    Text(progression.name).tag(progression.id)
                }
            }
            .fixedSize()
            .disabled(model.progressions.isEmpty)

            Toggle("Loop", isOn: Binding(
                get: { model.loop },
                set: { model.setLoop($0) }
            ))
            .toggleStyle(.checkbox)

            Button {
                model.startProgression()
            } label: {
                Label("Play progression", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(NotePalette.accent)
            .disabled(model.progressionChords.isEmpty)

            Button { model.strumChord() } label: { Label("Strum chord", systemImage: "guitars") }
            Button("Stop") { model.stopEverything() }

            if let beat = model.progressionSnapshot.countInBeat {
                Text("Count in… \(beat)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(NotePalette.accent)
            }
        }
    }


    private func readout(_ model: NoteAssociationModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(label: "Key", value: model.keyName, tint: NotePalette.color(for: .root))
                ModuleStat(label: "Over", value: model.chord?.name ?? "—")
                ModuleStat(label: "Solo with",
                           value: model.pentatonicNotes.map { $0.name() }.joined(separator: " "),
                           tint: NotePalette.color(for: .pentatonic))
            }
            key
            ModuleProse(paragraphs: prose(model))
        }
    }

    /// A legend, because three layers of meaning on one neck is exactly the
    /// place a reader needs telling what the colours mean.
    private var key: some View {
        HStack(spacing: 16) {
            legend(NotePalette.color(for: .root), "Chord tone")
            legend(NotePalette.color(for: .pentatonic), "Pentatonic")
            legend(NotePalette.color(for: .outsideShape), "Rest of the scale")
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func prose(_ model: NoteAssociationModuleModel) -> [String] {
        guard let chord = model.chord else { return [] }
        return [
            "Everything in \(model.keyName) is on the neck at once, coloured by what it is doing over \(chord.name) right now. The chord tones are the notes that land; the pentatonic is the safe ground around them; the rest of the scale is available but wants more care.",
            "Play the progression and watch the colours move while the dots stay still. Not one note shifts — what changes is each note's *job*, because the chord underneath moved. That is the whole idea: you are not learning where the notes are, you are learning what they mean at a given moment.",
            "Turn the layers off one at a time. Chord tones alone is arpeggio practice; pentatonic alone is where most solos live; all three is what an improviser is actually seeing."
        ]
    }
}
