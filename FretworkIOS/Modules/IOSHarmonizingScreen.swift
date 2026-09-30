import SwiftUI

/// The Harmonizing module on iOS.
///
/// Portrait reuses the Mac `HarmonizingModuleScreen` verbatim (D-18).
/// Landscape is the M2 arrangement (D-20/D-22): ‹ › step through the seven
/// chords of the key (I→vii°), and the drawer holds the key, mode, labels,
/// Play chord and the explanation. The voicings are fixed shapes drawn in
/// standard tuning, so the standard-tuning notice is kept (D-12).
struct IOSHarmonizingScreen: View {
    @Bindable var state: AppState

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var landscapeModel: HarmonizingModuleModel?

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                if let model = landscapeModel {
                    IOSHarmonizingLandscape(state: state, model: model)
                } else {
                    Color.clear
                        .task {
                            if landscapeModel == nil {
                                landscapeModel = state.makeHarmonizingModuleModel()
                                state.refreshSamplePlaybackReadiness()
                            }
                        }
                }
            } else {
                HarmonizingModuleScreen(state: state)
            }
        }
        .background(NotePalette.backdrop)
    }
}

// MARK: - Landscape (M2)

private struct IOSHarmonizingLandscape: View {
    let state: AppState
    let model: HarmonizingModuleModel
    @State private var labelMode: FretboardLabelMode = .degrees

    private var dots: [FretboardDot] {
        labelMode == .notes
            ? model.dots.showingNoteNames(in: Tunings.standard)
            : model.dots
    }

    private var subtitle: String {
        guard let chord = model.chord else { return model.keyName }
        return IOSModuleLandscapeFormat.harmonizingSubtitle(roman: chord.roman, chordName: chord.name)
    }

    var body: some View {
        IOSModuleLandscapeScaffold(
            title: IOSModuleScreenTitle.title(for: .harmonizing),
            subtitle: subtitle,
            tuning: state.tuning,
            isFixedShapeModule: true,
            state: state,
            neck: {
                FretboardBoardView(
                    dots: dots,
                    frets: model.highestFret,
                    tuning: Tunings.standard,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
            },
            leadingAction: .step(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous chord",
                disabled: model.degree == 0,
                action: { withAnimation(FretworkMotion.gravity) { model.selectDegree(model.degree - 1) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Next chord",
                disabled: model.degree == 6,
                action: { withAnimation(FretworkMotion.gravity) { model.selectDegree(model.degree + 1) } }
            ),
            drawerTitle: "Key & chord",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSHarmonizingDrawer(state: state, model: model, labelMode: $labelMode)
            },
            bandMode: .normal,
            guidedRunStepText: "",
            onStopGuidedRun: {}
        )
        .onDisappear { model.stop() }
    }
}

// MARK: - Drawer

private struct IOSHarmonizingDrawer: View {
    let state: AppState
    let model: HarmonizingModuleModel
    @Binding var labelMode: FretboardLabelMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PitchClassPicker(
                    title: "Key",
                    selection: model.keyRoot,
                    onSelect: model.selectKeyRoot
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Chord")
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

                StandardTuningNotice(tuning: state.tuning, what: "These voicings")
                IOSModulePlaybackNotice(state: state)

                HStack(spacing: 12) {
                    Button {
                        model.strum()
                    } label: {
                        Label("Play chord", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(NotePalette.accent)
                    .disabled(model.voicing == nil || !state.isSamplePlaybackReady)

                    Button("Stop") { model.stop() }
                        .buttonStyle(.glass)
                }

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
        Picker("Labels", selection: $labelMode) {
            Text("Notes").tag(FretboardLabelMode.notes)
            Text("Numbers").tag(FretboardLabelMode.degrees)
        }
        .pickerStyle(.menu)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            if let chord = model.chord {
                let tones = model.stackedTones.map { $0.name() }.joined(separator: ", ")
                Text("Take the \(ordinal(model.degree + 1)) note of \(model.keyName), then the note two above it, then two above that: \(tones). Stack those and you have \(chord.name) — the \(chord.roman) chord of the key.")
                Text("Nobody decided \(chord.roman) should be \(qualityWord(chord.quality)). It falls out of the spacing: the scale's own gaps decide the chord's quality. Step through the degrees and the same pattern appears in every key.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func ordinal(_ value: Int) -> String {
        switch value {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(value)th"
        }
    }

    private func qualityWord(_ quality: String) -> String {
        switch quality {
        case "maj": "major"
        case "min": "minor"
        case "dim": "diminished"
        default: quality
        }
    }
}
