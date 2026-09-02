import SwiftUI

/// Octaves — the same note higher on the neck, plus a recall round.
struct OctavesModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: OctavesModuleModel?
    @State private var showsFullNeck = false
    @State private var labelMode: FretboardLabelMode = .notes

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = state.makeOctavesModuleModel() }
            state.refreshSamplePlaybackReadiness()
        }
        .onChange(of: state.tuning) { _, tuning in model?.retune(to: tuning) }
        .onDisappear {
            model?.stopRecall()
            model?.stop()
        }
    }

    private func content(_ model: OctavesModuleModel) -> some View {
        let dots = labelMode == .notes ? model.dots : model.dots.map { dot in
            var numbered = dot
            if dot.label != "?" { numbered.label = dot.id.contains("target") ? "8" : "1" }
            return numbered
        }
        return ModuleLayout(module: .octaves, state: state) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                controls(model)
            }
        } stage: {
            VStack(alignment: .trailing, spacing: 8) {
                FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: model.highestFret)
                // Moving the shape up or down the neck is this module's
                // main non-root interaction, so it sits at the neck's own
                // ends now rather than as two more buttons in the row above.
                FretboardEdgeNav(
                    onPrevious: model.challenge.isRunning ? nil : { model.moveAnchor(by: -1) },
                    onNext: model.challenge.isRunning ? nil : { model.moveAnchor(by: 1) }
                ) {
                    FretboardBoardView(
                        dots: dots,
                        frets: showsFullNeck ? 22 : model.highestFret,
                        tuning: model.tuning,
                        flipped: state.isFretboardFlipped,
                        pulses: model.pulses,
                        // One board, two meanings: outside a round a tap
                        // moves the shape; inside one it is the answer.
                        onHit: { hit in
                            let position = Self.position(of: hit)
                            if model.challenge.isAcceptingAnswers {
                                model.answerCell(string: position.string, fret: position.fret)
                            } else {
                                model.selectAnchor(string: position.string, fret: position.fret)
                            }
                        }
                    )
                    .moduleLiveNoteGlow(state: state, dots: dots, frets: showsFullNeck ? 22 : model.highestFret, tuning: model.tuning, flipped: state.isFretboardFlipped)
                    .frame(minHeight: 260)
                }
            }
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: OctavesModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PitchClassPicker(title: "ROOT", selection: model.rootPitchClass, onSelect: model.selectRoot)
                .moduleNotesCard()

            HStack(spacing: 12) {
                FretboardLabelPicker(selection: $labelMode)
                Button {
                    model.hearOctave()
                } label: {
                    Label("Hear octave", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(NotePalette.accent)
                .disabled(model.currentShape == nil)

                Spacer()
                challengeControls(model)
            }
            .moduleOptionsCard()
        }
    }

    @ViewBuilder
    private func challengeControls(_ model: OctavesModuleModel) -> some View {
        switch model.challenge.phase {
        case .idle:
            Button("Start recall") { model.startRecall() }
                .disabled(model.shapes.isEmpty)
        case .prompt:
            HStack(spacing: 8) {
                Text("Where is the octave?")
                    .font(.callout)
                    .foregroundStyle(NotePalette.accent)
                Button("Stop") { model.stopRecall() }
            }
        case .incorrect:
            HStack(spacing: 8) {
                Text("Not that one.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button("Try again") { model.challenge.retry() }
                Button("Stop") { model.stopRecall() }
            }
        case .correct:
            HStack(spacing: 8) {
                Text("That's it.")
                    .font(.callout)
                    .foregroundStyle(NotePalette.color(for: .root))
                Button(model.challenge.index + 1 == model.challenge.total ? "Finish round" : "Next octave") {
                    model.challenge.next()
                }
                .buttonStyle(.borderedProminent)
                .tint(NotePalette.accent)
            }
        case .complete:
            HStack(spacing: 8) {
                Text("\(model.challenge.correctCount) of \(model.challenge.total)")
                    .font(.callout.weight(.medium))
                Button("Again") { model.challenge.restart() }
                Button("Done") { model.stopRecall() }
            }
        }
    }


    private func readout(_ model: OctavesModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(label: "Root", value: model.rootPitchClass.name(),
                           tint: NotePalette.color(for: .root))
                ModuleStat(label: "Shape", value: model.fretOffset.map { "+2 strings, \($0) frets" } ?? "—")
                ModuleStat(label: "Positions", value: "\(model.shapes.count)")
                if model.challenge.isRunning {
                    ModuleStat(label: "Round", value: "\(min(model.challenge.index + 1, model.challenge.total)) / \(model.challenge.total)")
                }
            }
            ModuleProse(paragraphs: prose(model))
        }
    }

    private func prose(_ model: OctavesModuleModel) -> [String] {
        var paragraphs = [
            "An octave is the same note twice — same letter, twice the frequency. On the neck it is a shape you can move rather than a position you memorise: put a finger on the root, skip a string, and the octave is a couple of frets further along."
        ]
        if let offset = model.fretOffset {
            if offset == 3 {
                paragraphs.append("This one is **three** frets across, not two. The B string is tuned a major third above the G rather than a fourth, so every shape crossing that pair stretches by a fret. It is the single exception that catches everyone out.")
            } else {
                paragraphs.append("Two strings up and \(offset) frets across. The shape holds anywhere on the neck — slide it and the octave comes with it.")
            }
        }
        if model.challenge.isRunning {
            paragraphs.append("Find the octave of the highlighted root and tap it. A wrong answer plays what you actually picked, so you can hear that it is not an octave.")
        }
        return paragraphs
    }

    private static func position(of hit: FretboardHit) -> FretPosition {
        switch hit {
        case .dot(let dot): dot.position
        case .cell(let position): position
        }
    }
}
