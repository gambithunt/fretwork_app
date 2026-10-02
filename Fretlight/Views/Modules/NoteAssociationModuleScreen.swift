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
            #if DEBUG
            if ModuleRunSnapshot.forcedRun != .idle {
                model?.debugForceRun(ModuleRunSnapshot.forcedRun)
            }
            #endif
        }
        .onChange(of: state.tuning) { _, tuning in model?.retune(to: tuning) }
        .onDisappear { model?.stopEverything() }
    }

    private func content(_ model: NoteAssociationModuleModel) -> some View {
        ModuleLayout(module: .noteAssociation, state: state) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                Self.controls(model)
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
                .moduleLiveNoteGlow(state: state, dots: model.dots, frets: showsFullNeck ? 22 : model.highestFret, tuning: model.tuning, flipped: state.isFretboardFlipped)
                .frame(minHeight: 260)
            }
        } readout: {
            readout(model)
        }
    }

    static func controls(_ model: NoteAssociationModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PitchClassPicker(title: "KEY", selection: model.keyRoot, onSelect: model.selectKeyRoot)
                .moduleNotesCard()

            // Three rows, rebuilt to the owner's balance: row 1 is what to
            // show (Mode · Labels · Layers), row 2 is the chord degree row at
            // full width so its seven chips stay one line, row 3 is the
            // progression (with Loop beside it) and the actions together.
            ModuleControlCard {
                Picker("Mode", selection: Binding(
                    get: { model.isMajor },
                    set: { model.selectMajor($0) }
                )) {
                    Text("Major").tag(true)
                    Text("Minor").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                .moduleMenuPicker()
                .moduleControlCell(caption: "MODE")

                Picker("Labels", selection: Binding(
                    get: { model.labelMode },
                    set: { model.setLabelMode($0) }
                )) {
                    Text("Notes").tag(NoteAssociationModuleModel.LabelMode.notes)
                    Text("Numbers").tag(NoteAssociationModuleModel.LabelMode.degrees)
                }
                .labelsHidden()
                .fixedSize()
                .moduleMenuPicker()
                .moduleControlCell(caption: "LABELS")

                // The layer switches. Seeing the scale alone, or the chord
                // tones alone, is a different exercise from seeing all three
                // at once. Chips, not the macOS-only checkbox style, so the
                // same control works on the Mac and on touch. One line of
                // `ToggleChip`s — not a `ToggleChipGrid` — so the three layer
                // chips stay on a single line inside their cell.
                ModuleChipRowLayout {
                    ToggleChip(
                        title: "Chord tones",
                        isOn: model.showsChordTones,
                        tint: NotePalette.accent,
                        onTap: { model.setLayer(chordTones: !model.showsChordTones) },
                        help: "Show the notes of the chord in focus"
                    )
                    ToggleChip(
                        title: "Pentatonic",
                        isOn: model.showsPentatonic,
                        tint: NotePalette.accent,
                        onTap: { model.setLayer(pentatonic: !model.showsPentatonic) },
                        help: "Show the safe notes around them"
                    )
                    ToggleChip(
                        title: "Rest of scale",
                        isOn: model.showsScale,
                        tint: NotePalette.accent,
                        onTap: { model.setLayer(scale: !model.showsScale) },
                        help: "Show the rest of the key's scale"
                    )
                }
                .moduleControlCell(caption: "LAYERS")

                // The chord degree row keeps all seven chips on one line; the
                // flow layout measures that line as the cell's natural width.
                // It starts its own row (Mode · Labels · Layers sit above) and
                // shares it with the progression-and-play group when that fits.
                ChipPicker(
                    values: Array(model.chords.indices),
                    selection: model.focusedDegree,
                    tint: { _ in NotePalette.accent },
                    onSelect: model.selectDegree,
                    isEmphasized: { model.playingDegree == $0 },
                    accessibilityLabel: { "\(model.chords[$0].roman), \(model.chords[$0].name)" },
                    singleLine: true
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
                .moduleControlCell(caption: "CHORD")
                .moduleControlRowBreak()

                // Progression, Loop and the actions are ONE flow cell, so they
                // never split: beside the chord chips when the row has room,
                // otherwise together on their own row at the trailing edge.
                // Strum chord rides along as the other play action.
                HStack(alignment: .top, spacing: 24) {
                    HStack(spacing: 8) {
                        Picker("Progression", selection: Binding(
                            get: { model.progressionID },
                            set: { model.selectProgression($0) }
                        )) {
                            ForEach(model.progressions, id: \.id) { progression in
                                Text(progression.name).tag(progression.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .moduleMenuPicker()
                        .disabled(model.progressions.isEmpty)

                        ToggleChip(
                            title: "Loop",
                            isOn: model.loop,
                            tint: NotePalette.accent,
                            onTap: { model.setLoop(!model.loop) }
                        )
                    }
                    .moduleControlCell(caption: "PROGRESSION")

                    // The actions stay together in the last cell: the primary
                    // action, its Stop, and Strum chord — a secondary action that
                    // belongs with the others rather than a lonely cell of its own.
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(action: { model.startProgression() }) {
                                Label {
                                    ModuleCountInLabel(
                                        title: "Play progression",
                                        countInBeat: model.progressionSnapshot.countInBeat
                                    )
                                } icon: {
                                    Image(systemName: "play.fill")
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 132)
                            }
                            .modulePrimaryButton()
                            .disabled(model.progressionChords.isEmpty)
                            .accessibilityLabel(model.progressionSnapshot.countInBeat.map { "Count in… \($0)" } ?? "Play progression")

                            Button(action: { model.strumChord() }) {
                                Label("Strum chord", systemImage: "guitars")
                            }
                            .moduleSecondaryButton()

                            Button(action: { model.stopEverything() }) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .moduleSecondaryButton()
                        }
                    }
                    .moduleControlCell(caption: "PLAY", alignment: .trailing)
                }
                // Natural width: the two inner cells must not stretch and
                // squeeze each other (that truncated Strum and Stop to "S…").
                .fixedSize(horizontal: true, vertical: false)
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
