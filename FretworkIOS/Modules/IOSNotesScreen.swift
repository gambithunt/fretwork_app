import SwiftUI

/// Notes on the fretboard on iOS, built on the shared `IOSModuleScaffold`
/// (D-11/D-18): the board is the input *and* the output — tap an empty cell
/// to drop a note, tap a dot to hear it again, long-press to remove one —
/// while the bottom corners hold Clear and ▶ Play all (D-26).
struct IOSNotesScreen: View {
    @Bindable var state: AppState

    @State private var model: NotesModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSNotesStage(state: state, model: model)
            } else {
                Color.clear
                    .task {
                        if model == nil {
                            model = state.makeNotesModuleModel()
                            state.refreshSamplePlaybackReadiness()
                        }
                    }
            }
        }
        .background(NotePalette.backdrop)
    }
}

private struct IOSNotesStage: View {
    let state: AppState
    let model: NotesModuleModel
    @State private var showsFullNeck = false

    private var canPlay: Bool { !model.placed.isEmpty && state.isSamplePlaybackReady }

    var body: some View {
        IOSModuleScaffold(
            title: IOSModuleScreenTitle.title(for: .notes),
            subtitle: IOSModuleLandscapeFormat.notesPlacedSubtitle(count: model.placed.count),
            tuning: model.tuning,
            isFixedShapeModule: false,
            state: state,
            neck: {
                FretboardBoardView(
                    dots: model.dots,
                    frets: model.highestFret,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses,
                    // A hit is either an existing dot or an empty cell; both
                    // carry a position and the module treats them the same
                    // way — tapping a dot replays it, tapping a cell places
                    // one (NotesModuleModel.tapCell).
                    onHit: { hit in
                        let position = Self.position(of: hit)
                        model.tapCell(string: position.string, fret: position.fret)
                    },
                    onLongPress: { hit in
                        let position = Self.position(of: hit)
                        model.longPressCell(string: position.string, fret: position.fret)
                    }
                )
            },
            leadingAction: .step(
                systemImage: "trash",
                accessibilityLabel: "Clear all notes",
                disabled: model.placed.isEmpty,
                action: { model.clearAll() }
            ),
            trailingAction: .step(
                systemImage: "play.fill",
                accessibilityLabel: "Play all notes",
                disabled: !canPlay,
                action: { model.playAll() }
            ),
            drawerTitle: "Notes & neck",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSNotesDrawer(state: state, model: model, showsFullNeck: $showsFullNeck)
            },
            bandMode: .normal,
            guidedRunStepText: "",
            onStopGuidedRun: {},
            onTuningChange: { tuning in
                // A tuning change re-pitches every dot, so anything still
                // sounding belongs to the old tuning.
                model.stop()
                model.tuning = tuning
            },
            frets: model.highestFret,
            focusFret: IOSModulePortraitStrip.focusFret(for: model.dots, highestFret: model.highestFret)
        )
        .onChange(of: showsFullNeck) { _, expanded in
            // A tap past fret 12 has to resolve to a real cell, so widening
            // the drawn board widens the model's floor too.
            model.highestFret = expanded ? 22 : LearningModule.notes.highestFret
        }
        .onDisappear { model.stop() }
    }

    private static func position(of hit: FretboardHit) -> FretPosition {
        switch hit {
        case .dot(let dot): dot.position
        case .cell(let position): position
        }
    }
}

// MARK: - Drawer

private struct IOSNotesDrawer: View {
    let state: AppState
    let model: NotesModuleModel
    @Binding var showsFullNeck: Bool

    private static let allPitchClasses = (0..<12).map(PitchClass.init)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap to toggle every position")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    // Twelve independent toggles reflecting the board, not one
                    // selection — ToggleChipGrid, not PitchClassPicker. Menu
                    // taps stay silent; only a tap on the fretboard itself
                    // sounds anything.
                    ToggleChipGrid(
                        values: Self.allPitchClasses,
                        isActive: model.isNoteActive,
                        tint: NotePalette.color(for:),
                        onTap: model.toggleNote,
                        help: { pitchClass in
                            pitchClass.enharmonicAlias.map { "\(pitchClass.name()) = \($0)" } ?? pitchClass.name()
                        },
                        accessibilityValue: { _, active in active ? "every position placed" : "not fully placed" }
                    ) { pitchClass, isActive in
                        Text(pitchClass.name())
                            .font(.callout.weight(.medium))
                            .foregroundStyle(isActive ? Color.black : NotePalette.color(for: pitchClass))
                    }
                }

                Toggle(isOn: $showsFullNeck) {
                    Label("Full neck (22 frets)", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.callout)
                }
                .tint(NotePalette.accent)

                IOSModulePlaybackNotice(state: state)

                explanation
            }
            .padding(20)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            ForEach(Array(prose.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The same copy the Mac readout draws, so the lesson reads identically in
    /// both orientations.
    private var prose: [String] {
        guard !model.placed.isEmpty else {
            return [
                "The board is empty. \(model.discovery.message) Tap anywhere on the neck to drop a note where your finger lands — it names itself and plays. Tap a note button above to light up every position of that note at once, tap an existing dot to hear it again, and long-press a dot to remove just that one. Each of the twelve notes has its own colour.",
            ]
        }
        var paragraphs: [String] = [model.discovery.message]
        if !model.discovery.alternatives.isEmpty {
            paragraphs[0] += " Also possible: \(model.discovery.alternatives.map(\.symbol).joined(separator: ", "))."
        }
        let hints = model.enharmonicHints
        if !hints.isEmpty {
            paragraphs.append("Same pitch, two names: \(hints.joined(separator: ", ")). Which spelling is right depends on the key you are in, not on the fret.")
        }
        return paragraphs
    }
}
