import SwiftUI

/// Notes on the fretboard — the first module, and the one that exercises every
/// interaction path workstream 004's board provides.
///
/// See `NotesModuleModel` for the rules; this is only their presentation.
struct NotesModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: NotesModuleModel?
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
            if model == nil { model = state.makeNotesModuleModel() }
            model?.tuning = state.tuning
            model?.highestFret = showsFullNeck ? 22 : LearningModule.notes.highestFret
            // A graph rebuild replaces the player, so readiness is re-checked
            // on every appearance rather than trusted from last time.
            state.refreshSamplePlaybackReadiness()
        }
        .onChange(of: state.tuning) { _, tuning in
            // A tuning change re-pitches every dot on the board, so anything
            // still sounding belongs to the old tuning.
            model?.stop()
            model?.tuning = tuning
        }
        .onChange(of: showsFullNeck) { _, expanded in
            model?.highestFret = expanded ? 22 : LearningModule.notes.highestFret
        }
        // Leaving the screen must silence it. Without this a run started here
        // keeps playing over whatever the player navigates to — one of the
        // cancellation cases workstream 006 names explicitly.
        .onDisappear { model?.stop() }
    }

    private func content(_ model: NotesModuleModel) -> some View {
        ModuleLayout(module: .notes, state: state) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                controls(model)
            }
        } stage: {
            VStack(alignment: .trailing, spacing: 8) {
                FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: LearningModule.notes.highestFret)
                FretboardBoardView(
                    dots: model.dots,
                    frets: model.highestFret,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses,
                    // A hit is either an existing dot or an empty cell; both
                    // carry a position and the module treats them the same
                    // way — tapping a dot replays it, tapping a cell places
                    // one.
                    onHit: { hit in
                        let position = Self.position(of: hit)
                        model.tapCell(string: position.string, fret: position.fret)
                    },
                    onLongPress: { hit in
                        let position = Self.position(of: hit)
                        model.longPressCell(string: position.string, fret: position.fret)
                    }
                )
                .frame(minHeight: 260)
            }
        } readout: {
            readout(model)
        }
    }

    private static let allPitchClasses = (0..<12).map(PitchClass.init)

    private func controls(_ model: NotesModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES — TAP TO TOGGLE EVERY POSITION")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                // Twelve independent toggles reflecting the board, not one
                // selection — `ToggleChipGrid`, not `PitchClassPicker`. Menu
                // taps stay silent; only a tap on the fretboard itself
                // (`tapCell`, below) sounds anything.
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
            .moduleNotesCard()

            HStack(spacing: 12) {
                Button {
                    model.playAll()
                } label: {
                    Label("Play all", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(NotePalette.accent)
                .disabled(model.placed.isEmpty)

                Button("Stop") { model.stop() }
                Button("Clear all") { model.clearAll() }
                    .disabled(model.placed.isEmpty)
            }
            .moduleOptionsCard()
        }
    }

    private func readout(_ model: NotesModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHORD")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(model.chordLabel)
                        .font(.title.weight(.bold))
                    if !model.discovery.alternatives.isEmpty {
                        Text("Also: \(model.discovery.alternatives.map(\.symbol).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 180, alignment: .leading)
                ModuleStat(
                    label: "Notes",
                    value: model.present.isEmpty ? "—" : model.present.map { $0.pitchClass.name() }.joined(separator: " ")
                )
                ModuleStat(label: "Placed", value: "\(model.placed.count)")
            }

            ModuleProse(paragraphs: prose(model))
        }
    }

    private static func position(of hit: FretboardHit) -> FretPosition {
        switch hit {
        case .dot(let dot): dot.position
        case .cell(let position): position
        }
    }

    private func prose(_ model: NotesModuleModel) -> [String] {
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
