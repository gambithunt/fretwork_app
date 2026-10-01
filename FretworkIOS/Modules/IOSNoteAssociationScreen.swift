import SwiftUI

/// The Note association module on iOS, built on the shared
/// `IOSModuleScaffold` (D-11/D-18): ‹ › step through the seven chords of the
/// key (I→vii°, the chord underneath the layered neck), and the drawer holds
/// the key, mode, labels, the three layer chips, the progression and its
/// loop, Play progression / Strum chord, and the explanation.
struct IOSNoteAssociationScreen: View {
    @Bindable var state: AppState

    @State private var model: NoteAssociationModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSNoteAssociationStage(state: state, model: model)
            } else {
                Color.clear
                    .task {
                        if model == nil {
                            model = state.makeNoteAssociationModuleModel()
                            state.refreshSamplePlaybackReadiness()
                        }
                    }
            }
        }
        .background(NotePalette.backdrop)
    }
}

private struct IOSNoteAssociationStage: View {
    let state: AppState
    let model: NoteAssociationModuleModel

    /// iPad draws the full 22-fret neck; the phone keeps the module's range.
    private var boardFrets: Int {
        IOSModuleBoard.frets(idiom: UIDevice.current.userInterfaceIdiom, moduleFrets: model.highestFret)
    }

    private var isRunActive: Bool {
        model.progressionSnapshot.status != .idle
    }

    private var subtitle: String {
        guard let chord = model.chord else { return model.keyName }
        return IOSModuleLandscapeFormat.noteAssociationSubtitle(roman: chord.roman, chordName: chord.name)
    }

    private var guidedStepText: String {
        guard isRunActive else { return "" }
        let next = (model.progressionSnapshot.currentIndex ?? -1) + 1
        let chords = model.progressionChords
        guard chords.indices.contains(next) else { return "" }
        return IOSModuleLandscapeFormat.noteAssociationStepText(nextChord: chords[next])
    }

    var body: some View {
        IOSModuleScaffold(
            title: IOSModuleScreenTitle.title(for: .noteAssociation),
            subtitle: subtitle,
            tuning: model.tuning,
            boardTuning: model.tuning,
            isFixedShapeModule: false,
            state: state,
            neck: {
                FretboardBoardView(
                    dots: model.dots,
                    frets: boardFrets,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
            },
            leadingAction: .step(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous chord",
                disabled: isRunActive || model.focusedDegree == 0,
                action: { withAnimation(FretworkMotion.gravity) { model.selectDegree(model.focusedDegree - 1) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Next chord",
                disabled: isRunActive || model.focusedDegree == 6,
                action: { withAnimation(FretworkMotion.gravity) { model.selectDegree(model.focusedDegree + 1) } }
            ),
            drawerTitle: "Key & layers",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSNoteAssociationDrawer(state: state, model: model, isRunActive: isRunActive)
            },
            isRunActive: isRunActive,
            guidedRunStepText: guidedStepText,
            onTuningChange: { model.retune(to: $0) },
            frets: boardFrets,
            focusFret: IOSModulePortraitStrip.focusFret(for: model.dots, highestFret: boardFrets)
        )
        .onDisappear { model.stopEverything() }
    }
}

// MARK: - Drawer

private struct IOSNoteAssociationDrawer: View {
    let state: AppState
    let model: NoteAssociationModuleModel
    let isRunActive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PitchClassPicker(
                    title: "Key",
                    selection: model.keyRoot,
                    onSelect: model.selectKeyRoot
                )
                .disabled(isRunActive)
                .iosRunDimmed(isRunActive)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode & labels")
                        .font(.headline)
                    VStack(spacing: 12) {
                        LabeledContent("Mode") {
                            modePicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        LabeledContent("Labels") {
                            labelPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .disabled(isRunActive)

                layers
                    .disabled(isRunActive)
                    .iosRunDimmed(isRunActive)
                progression
                explanation
            }
            .padding(20)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { model.isMajor },
            set: { model.selectMajor($0) }
        )) {
            Text("Major").tag(true)
            Text("Minor").tag(false)
        }
        .pickerStyle(.menu)
    }

    private var labelPicker: some View {
        Picker("Labels", selection: Binding(
            get: { model.labelMode },
            set: { model.setLabelMode($0) }
        )) {
            Text("Notes").tag(NoteAssociationModuleModel.LabelMode.notes)
            Text("Numbers").tag(NoteAssociationModuleModel.LabelMode.degrees)
        }
        .pickerStyle(.menu)
    }

    /// The layer switches: chord tones alone is arpeggio practice, pentatonic
    /// alone is where most solos live. Chips, not checkboxes, so a second fact
    /// (a chord tone that is also pentatonic) can keep both visible.
    private var layers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers")
                .font(.headline)
            IOSFlowLayout(spacing: 8) {
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
        }
    }

    private var progression: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progression")
                .font(.headline)
            HStack(spacing: 12) {
                Picker("Progression", selection: Binding(
                    get: { model.progressionID },
                    set: { model.selectProgression($0) }
                )) {
                    ForEach(model.progressions, id: \.id) { progression in
                        Text(progression.name).tag(progression.id)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(isRunActive || model.progressions.isEmpty)

                ToggleChip(
                    title: "Loop",
                    isOn: model.loop,
                    tint: NotePalette.accent,
                    onTap: { model.setLoop(!model.loop) }
                )
                .disabled(isRunActive)
                .iosRunDimmed(isRunActive)
            }

            IOSModulePlaybackNotice(state: state)

            HStack(spacing: 12) {
                Button {
                    if isRunActive { model.stopEverything() } else { model.startProgression() }
                } label: {
                    Label(isRunActive ? "Stop" : "Play progression", systemImage: isRunActive ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(isRunActive ? .red : NotePalette.accent)
                .disabled(!isRunActive && (model.progressionChords.isEmpty || !state.isSamplePlaybackReady))

                Button {
                    model.strumChord()
                } label: {
                    Label("Strum chord", systemImage: "guitars")
                }
                .buttonStyle(.glass)
                .disabled(isRunActive || model.chord == nil || !state.isSamplePlaybackReady)

                Button("Stop") { model.stopEverything() }
                    .buttonStyle(.glass)
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            if let chord = model.chord {
                Text("Everything in \(model.keyName) is on the neck at once, coloured by what it is doing over \(chord.name) right now. The chord tones are the notes that land; the pentatonic is the safe ground around them; the rest of the scale is available but wants more care.")
                Text("Play the progression and watch the colours move while the dots stay still. Not one note shifts — what changes is each note's job, because the chord underneath moved.")
                Text("Turn the layers off one at a time. Chord tones alone is arpeggio practice; pentatonic alone is where most solos live; all three is what an improviser is actually seeing.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
