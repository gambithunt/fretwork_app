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
                FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: model.highestFret) {
                    layersHeader(model)
                }
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
            // show (Mode · Labels · Chord, the chord chips wrapping whole to
            // their own row when narrow), row 2 is a full-width group with
            // the progression (and Loop) leading and the play actions
            // trailing.
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

                // The layer switches moved out of the card onto the board's
                // header row (the SHOW chips beside Full neck), so the card's
                // first row is now Mode · Labels · Chord.

                // The chord degree row keeps all seven chips on one line; the
                // flow layout measures that line as the cell's natural width.
                // It flows beside Mode and Labels when that fits, and wraps
                // whole to its own row otherwise.
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

                // Progression, Loop and the actions are ONE full-width flow
                // cell that always starts its own row: the progression part
                // at the leading edge, the play actions at the trailing edge,
                // flexible space between. When the row is too narrow for both
                // on one line, the play part wraps below — still trailing —
                // and nothing truncates.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        Self.progressionGroup(model)
                        Spacer(minLength: 24)
                        Self.playGroup(model)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Self.progressionGroup(model)
                        Self.playGroup(model)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .moduleControlFullWidth()
            }
        }
    }

    /// The progression picker and Loop, kept as one natural-width cell so they
    /// never stretch to fill the row's flexible space.
    private static func progressionGroup(_ model: NoteAssociationModuleModel) -> some View {
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
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The play actions stay together: the primary action, its Stop, and
    /// Strum chord — a secondary action that belongs with the others rather
    /// than a lonely cell of its own. Natural width, so the row's flexible
    /// space pushes it to the trailing edge instead of stretching the buttons
    /// apart (which truncated Strum and Stop to "S…").
    private static func playGroup(_ model: NoteAssociationModuleModel) -> some View {
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
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The SHOW caption and the three layer chips for the board's header row,
    /// each carrying its layer's role colour as its dot — the same colours the
    /// board uses. On = lit chip with a filled dot; off = dim chip with a
    /// hollow ring dot.
    @ViewBuilder
    private func layersHeader(_ model: NoteAssociationModuleModel) -> some View {
        HStack(spacing: 8) {
            Text("SHOW")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            RoleDotToggleChip(
                title: "Chord tones",
                isOn: model.showsChordTones,
                color: NotePalette.color(for: .root),
                onTap: { model.setLayer(chordTones: !model.showsChordTones) },
                help: "Show the notes of the chord in focus"
            )
            RoleDotToggleChip(
                title: "Pentatonic",
                isOn: model.showsPentatonic,
                color: NotePalette.color(for: .pentatonic),
                onTap: { model.setLayer(pentatonic: !model.showsPentatonic) },
                help: "Show the safe notes around them"
            )
            RoleDotToggleChip(
                title: "Rest of scale",
                isOn: model.showsScale,
                color: NotePalette.color(for: .outsideShape),
                onTap: { model.setLayer(scale: !model.showsScale) },
                help: "Show the rest of the key's scale"
            )
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
            ModuleProse(paragraphs: prose(model))
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
