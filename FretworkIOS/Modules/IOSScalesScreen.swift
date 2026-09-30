import SwiftUI

/// The Scales module on iOS, built on the shared `IOSModuleScaffold`
/// (D-11/D-18): a single ▶ Practise button where the ‹ › step arrows would be
/// (D-26 — Scales has no positions to move along the neck) and a drawer
/// holding the root, quality, direction, labels, tempo and the explanation.
/// During a guided run the band switches to ■ Stop + the next note (D-27).
struct IOSScalesScreen: View {
    @Bindable var state: AppState

    @State private var model: ScalesModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSScalesStage(state: state, model: model)
            } else {
                Color.clear
                    .task {
                        if model == nil {
                            model = state.makeScalesModuleModel()
                            state.refreshSamplePlaybackReadiness()
                        }
                    }
            }
        }
        .background(NotePalette.backdrop)
    }
}

private struct IOSScalesStage: View {
    let state: AppState
    let model: ScalesModuleModel

    private var bandMode: IOSModuleBandMode {
        IOSSnapshot.guidedRunActive || model.guidedSnapshot.status != .idle
            ? .guidedRun
            : .normal
    }

    private var guidedStepText: String {
        // During the count-in `currentIndex` is nil, so fall back to the first
        // note of the run — it genuinely is the next one.
        guard let next = model.nextStep ?? model.sequence.first else { return "" }
        return IOSModuleLandscapeFormat.guidedRunStepText(next: next)
    }

    var body: some View {
        IOSModuleScaffold(
            title: IOSModuleScreenTitle.title(for: .scales),
            subtitle: IOSModuleLandscapeFormat.scalesSubtitle(
                scaleName: model.scaleName,
                direction: model.direction
            ),
            tuning: model.tuning,
            boardTuning: model.tuning,
            isFixedShapeModule: false,
            state: state,
            neck: {
                FretboardBoardView(
                    dots: model.dots,
                    frets: model.highestFret,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped
                )
            },
            // No positions to step through (D-26): the leading corner is a
            // single ▶ Practise action and there is no trailing control.
            leadingAction: IOSModuleBandAction(
                title: "Practise",
                systemImage: "play.fill",
                accessibilityLabel: "Practise",
                disabled: model.sequence.isEmpty || !state.isSamplePlaybackReady,
                action: { model.startGuided() }
            ),
            trailingAction: nil,
            drawerTitle: "Scale & key",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSScalesDrawer(state: state, model: model)
            },
            bandMode: bandMode,
            guidedRunStepText: guidedStepText,
            onStopGuidedRun: { model.stopGuided() },
            onTuningChange: { model.retune(to: $0) },
            frets: model.highestFret,
            focusFret: IOSModulePortraitStrip.focusFret(for: model.dots, highestFret: model.highestFret)
        )
        .onDisappear { model.stopGuided() }
    }
}

// MARK: - Drawer

private struct IOSScalesDrawer: View {
    let state: AppState
    let model: ScalesModuleModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PitchClassPicker(
                    title: "Root",
                    selection: model.rootPitchClass,
                    onSelect: model.selectRoot
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Scale")
                        .font(.headline)
                    VStack(spacing: 12) {
                        LabeledContent("Quality") {
                            qualityPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        LabeledContent("Direction") {
                            directionPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        LabeledContent("Labels") {
                            labelPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                tempo
                IOSModulePlaybackNotice(state: state)
                explanation
            }
            .padding(20)
        }
    }

    private var qualityPicker: some View {
        Picker("Quality", selection: Binding(
            get: { model.quality },
            set: { model.selectQuality($0) }
        )) {
            Text("Major").tag(OneOctaveScaleQuality.major)
            Text("Natural minor").tag(OneOctaveScaleQuality.naturalMinor)
        }
        .pickerStyle(.menu)
    }

    private var directionPicker: some View {
        Picker("Direction", selection: Binding(
            get: { model.direction },
            set: { model.selectDirection($0) }
        )) {
            Text("Ascending").tag(ScalesModuleModel.Direction.ascending)
            Text("Up and down").tag(ScalesModuleModel.Direction.upDown)
        }
        .pickerStyle(.menu)
    }

    private var labelPicker: some View {
        Picker("Labels", selection: Binding(
            get: { model.labelMode },
            set: { model.selectLabelMode($0) }
        )) {
            Text("Notes").tag(ScalesModuleModel.LabelMode.notes)
            Text("Numbers").tag(ScalesModuleModel.LabelMode.degrees)
        }
        .pickerStyle(.menu)
    }

    /// The on-screen tempo handles are the model's `slower`/`faster` (the web's
    /// five presets, not a continuous slider). They drive the live session's
    /// tempo, so the reader can set the speed of the run they are about to
    /// start — or nudge a run's tempo between times through it.
    private var tempo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tempo")
                .font(.headline)
            HStack(spacing: 12) {
                Button { _ = model.slower() } label: { Image(systemName: "tortoise") }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Slower")
                Text("\(model.guidedSnapshot.tempoBpm) bpm")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { _ = model.faster() } label: { Image(systemName: "hare") }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Faster")
            }
            Text("A four-beat count-in, then one note per beat up the scale.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            Text("The \(model.scaleName) scale, one octave from its root. Eight notes: seven degrees and then the root again on top, which is what makes it sound finished rather than stopped.")
            if model.quality == .major {
                Text("Major is the reference every other scale is described against — its degrees are the plain numbers, and the minor scales are written as flattened versions of them.")
            } else {
                Text("Natural minor is the major scale with its 3rd, 6th and 7th flattened. Same notes as its relative major, started three semitones lower — which is why the shapes feel familiar before they sound familiar.")
            }
            if model.labelMode == .degrees {
                Text("Labelled by degree, so the shape reads the same in every key. Switch to notes when you want to learn where you are on the neck rather than what the shape is doing.")
            } else {
                Text("Labelled by note. Switch to degrees when you want the shape to read the same in every key.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
