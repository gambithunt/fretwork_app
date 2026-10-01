import SwiftUI

/// Octaves on iOS, built on the shared `IOSModuleScaffold` (D-11/D-18): ‹ ›
/// walk the octave shape along the neck and the subtitle reports which
/// position it is in, while the drawer holds the root, the label mode, "Hear
/// octave", the recall round and the explanation.
struct IOSOctavesScreen: View {
    @Bindable var state: AppState

    @State private var model: OctavesModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSOctavesStage(state: state, model: model)
            } else {
                Color.clear
                    .task {
                        if model == nil {
                            model = state.makeOctavesModuleModel()
                            state.refreshSamplePlaybackReadiness()
                        }
                    }
            }
        }
        .background(NotePalette.backdrop)
    }
}

private struct IOSOctavesStage: View {
    let state: AppState
    let model: OctavesModuleModel
    @State private var labelMode: FretboardLabelMode = .notes

    /// iPad draws the full 22-fret neck; the phone keeps the module's range.
    private var boardFrets: Int {
        IOSModuleBoard.frets(idiom: UIDevice.current.userInterfaceIdiom, moduleFrets: model.highestFret)
    }

    private var dots: [FretboardDot] {
        labelMode == .notes ? model.dots : model.dots.map { dot in
            var numbered = dot
            if dot.label != "?" { numbered.label = dot.id.contains("target") ? "8" : "1" }
            return numbered
        }
    }

    private var subtitle: String {
        IOSModuleLandscapeFormat.octavesPositionSubtitle(
            index: model.anchoredIndex,
            count: model.shapes.count
        )
    }

    /// A recall round pins the board to the prompt, so moving the anchor would
    /// move the question. The arrows stay visible (D-26) but inert.
    private var isNavDisabled: Bool { model.challenge.isRunning || model.anchoredIndex == nil }

    var body: some View {
        IOSModuleScaffold(
            title: IOSModuleScreenTitle.title(for: .octaves),
            subtitle: subtitle,
            tuning: model.tuning,
            boardTuning: model.tuning,
            isFixedShapeModule: false,
            state: state,
            neck: {
                FretboardBoardView(
                    dots: dots,
                    frets: boardFrets,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses,
                    // One board, two meanings: outside a round a tap moves the
                    // shape; inside one it is the answer.
                    onHit: { hit in
                        let position = Self.position(of: hit)
                        if model.challenge.isAcceptingAnswers {
                            model.answerCell(string: position.string, fret: position.fret)
                        } else {
                            model.selectAnchor(string: position.string, fret: position.fret)
                        }
                    }
                )
            },
            leadingAction: .step(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous position",
                disabled: isNavDisabled,
                action: { withAnimation(FretworkMotion.gravity) { model.moveAnchor(by: -1) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Next position",
                disabled: isNavDisabled,
                action: { withAnimation(FretworkMotion.gravity) { model.moveAnchor(by: 1) } }
            ),
            drawerTitle: "Root & recall",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSOctavesDrawer(state: state, model: model, labelMode: $labelMode)
            },
            isRunActive: false,
            guidedRunStepText: "",
            onTuningChange: { model.retune(to: $0) },
            frets: boardFrets,
            focusFret: IOSModulePortraitStrip.focusFret(for: dots, highestFret: boardFrets)
        )
        .onDisappear {
            model.stopRecall()
            model.stop()
        }
    }

    private static func position(of hit: FretboardHit) -> FretPosition {
        switch hit {
        case .dot(let dot): dot.position
        case .cell(let position): position
        }
    }
}

// MARK: - Drawer

private struct IOSOctavesDrawer: View {
    let state: AppState
    let model: OctavesModuleModel
    @Binding var labelMode: FretboardLabelMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PitchClassPicker(
                    title: "Root",
                    selection: model.rootPitchClass,
                    onSelect: model.selectRoot
                )

                LabeledContent("Labels") {
                    FretboardLabelPicker(selection: $labelMode)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Play")
                        .font(.headline)
                    Button {
                        model.hearOctave()
                    } label: {
                        Label("Hear octave", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(NotePalette.accent)
                    .disabled(model.currentShape == nil || !state.isSamplePlaybackReady)
                    IOSModulePlaybackNotice(state: state)
                }

                recallChallenge

                explanation
            }
            .padding(20)
        }
    }

    /// The recall controls, same phases as the Mac: a wrong answer is retried
    /// rather than marked and skipped, so the round is practice, not a test.
    @ViewBuilder
    private var recallChallenge: some View {
        switch model.challenge.phase {
        case .idle:
            Button {
                model.startRecall()
            } label: {
                Label("Start recall", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(model.shapes.isEmpty)
        case .prompt:
            HStack(spacing: 12) {
                Label("Where is the octave?", systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(NotePalette.accent)
                Spacer()
                Button("Stop") { model.stopRecall() }
                    .buttonStyle(.glass)
            }
        case .incorrect:
            HStack(spacing: 12) {
                Label("Not that one.", systemImage: "arrow.counterclockwise")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Try again") { model.challenge.retry() }
                    .buttonStyle(.glassProminent)
                    .tint(NotePalette.accent)
                Button("Stop") { model.stopRecall() }
                    .buttonStyle(.glass)
            }
        case .correct:
            HStack(spacing: 12) {
                Label("That's it.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(NotePalette.color(for: .root))
                Spacer()
                Button(model.challenge.index + 1 == model.challenge.total ? "Finish round" : "Next octave") {
                    model.challenge.next()
                }
                .buttonStyle(.glassProminent)
                .tint(NotePalette.accent)
            }
        case .complete:
            HStack(spacing: 12) {
                Text("\(model.challenge.correctCount) of \(model.challenge.total)")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Again") { model.challenge.restart() }
                    .buttonStyle(.glassProminent)
                    .tint(NotePalette.accent)
                Button("Done") { model.stopRecall() }
                    .buttonStyle(.glass)
            }
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

    private var prose: [String] {
        var paragraphs = [
            "An octave is the same note twice — same letter, twice the frequency. On the neck it is a shape you can move rather than a position you memorise: put a finger on the root, skip a string, and the octave is a couple of frets further along.",
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
}
