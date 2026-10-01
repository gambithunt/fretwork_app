import SwiftUI

/// Triads on iOS, built on the shared `IOSModuleScaffold` (D-11/D-18), with
/// two faces:
///
/// - **Shapes** — ‹ › walk every compact voicing, the subtitle naming the
///   chord and its inversion.
/// - **Paths** — ▶/■ start and stop the diatonic progression; while it runs,
///   the bottom band becomes the D-27 guided band (■ Stop + the next chord).
///
/// The drawer holds the exercise switch and, for whichever is selected, the
/// triad/double-stop/inversion or string-set/key controls, tempo, loop and the
/// explanation.
struct IOSTriadsScreen: View {
    @Bindable var state: AppState

    @State private var model: TriadsModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSTriadsStage(state: state, model: model)
            } else {
                Color.clear
                    .task {
                        if model == nil {
                            model = state.makeTriadsModuleModel()
                            state.refreshSamplePlaybackReadiness()
                            #if DEBUG
                            // The snapshot harness opens directly on the
                            // Paths face; nothing else forces that mode, and
                            // the guided-run shot drives a real session.
                            if IOSSnapshot.forcesTriadsPathMode {
                                model?.setPathMode(true)
                            }
                            if IOSSnapshot.guidedRunActive {
                                model?.startProgression(loop: false)
                            }
                            #endif
                        }
                    }
            }
        }
        .background(NotePalette.backdrop)
    }
}

private struct IOSTriadsStage: View {
    let state: AppState
    let model: TriadsModuleModel

    /// iPad draws the full 22-fret neck; the phone keeps the module's range.
    private var boardFrets: Int {
        IOSModuleBoard.frets(idiom: UIDevice.current.userInterfaceIdiom, moduleFrets: model.highestFret)
    }

    private var subtitle: String {
        if model.isPathMode {
            return IOSModuleLandscapeFormat.triadsPathSubtitle(
                chord: model.currentPathStep?.chord.name ?? "—",
                roman: model.currentPathStep?.chord.roman ?? "",
                index: model.currentPathStep == nil ? nil : model.pathStep,
                count: model.pathSteps.count
            )
        }
        let name = model.view == .doubleStops ? model.doubleStop.label : model.triad.name
        let inversion = model.view == .doubleStops ? nil : model.selectedInversion
        return IOSModuleLandscapeFormat.triadsShapeSubtitle(
            root: model.rootPitchClass,
            name: name,
            inversion: inversion
        )
    }

    private var isRunActive: Bool {
        guard model.isPathMode else { return false }
        return model.progressionSnapshot.status != .idle
    }

    private var guidedStepText: String {
        guard isRunActive else { return "" }
        return IOSModuleLandscapeFormat.triadsPathStepText(next: model.currentPathStep)
    }

    // The corners change meaning with the exercise: arrows walk the shapes,
    // while the path's start button turns into ■ Stop in place (D-27 revised)
    // and its separate Stop stays as a second, always-available way out.
    private var leadingAction: IOSModuleBandAction {
        if model.isPathMode {
            return .runToggle(
                title: "Play path",
                accessibilityLabel: "Play path",
                isRunActive: isRunActive,
                disabled: !isRunActive && (model.pathSteps.isEmpty || !state.isSamplePlaybackReady),
                start: { model.startProgression(loop: false) },
                stop: { model.stopEverything() }
            )
        }
        return .step(
            systemImage: "chevron.left",
            accessibilityLabel: "Previous position",
            disabled: model.voicings.isEmpty,
            action: { withAnimation(FretworkMotion.gravity) { model.movePosition(by: -1) } }
        )
    }

    private var trailingAction: IOSModuleBandAction {
        if model.isPathMode {
            return .step(
                systemImage: "stop.fill",
                accessibilityLabel: "Stop path",
                disabled: model.progressionSnapshot.status == .idle,
                action: { model.stopEverything() }
            )
        }
        return .step(
            systemImage: "chevron.right",
            accessibilityLabel: "Next position",
            disabled: model.voicings.isEmpty,
            action: { withAnimation(FretworkMotion.gravity) { model.movePosition(by: 1) } }
        )
    }

    var body: some View {
        IOSModuleScaffold(
            title: IOSModuleScreenTitle.title(for: .triads),
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
            leadingAction: leadingAction,
            trailingAction: trailingAction,
            drawerTitle: "Triad & key",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSTriadsDrawer(state: state, model: model, isRunActive: isRunActive)
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

private struct IOSTriadsDrawer: View {
    let state: AppState
    let model: TriadsModuleModel
    let isRunActive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PitchClassPicker(
                    title: model.isPathMode ? "Key" : "Root",
                    selection: model.isPathMode ? model.pathKeyRoot : model.rootPitchClass,
                    onSelect: model.selectRoot
                )
                .disabled(isRunActive)
                .iosRunDimmed(isRunActive)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercise")
                        .font(.headline)
                    Picker("Exercise", selection: Binding(
                        get: { model.isPathMode },
                        set: { model.setPathMode($0) }
                    )) {
                        Text("Shapes").tag(false)
                        Text("Paths").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                .disabled(isRunActive)

                if model.isPathMode {
                    pathControls
                } else {
                    shapeControls
                }

                IOSModulePlaybackNotice(state: state)

                explanation
            }
            .padding(20)
        }
    }

    // MARK: Shapes

    private var shapeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Triad") {
                triadPicker
                    .fixedSize(horizontal: true, vertical: false)
            }
            if model.view == .doubleStops {
                LabeledContent("Pair") {
                    doubleStopPicker
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                LabeledContent("Inversion") {
                    inversionPicker
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.playVoicing()
                } label: {
                    Label("Play shape", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(NotePalette.accent)
                .disabled(model.activeVoicing == nil || !state.isSamplePlaybackReady)

                Button("Stop") { model.stop() }
                    .buttonStyle(.glass)
            }
        }
    }

    private var triadPicker: some View {
        Picker("Triad", selection: Binding(
            get: { model.view == .doubleStops ? "doubleStops" : model.triad.short },
            set: { value in
                if value == "doubleStops" {
                    model.selectDoubleStop(model.doubleStop)
                } else if let triad = Triads.all.first(where: { $0.short == value }) {
                    model.selectTriad(triad)
                }
            }
        )) {
            ForEach(Triads.all, id: \.short) { triad in
                Text(triad.name).tag(triad.short)
            }
            Text("Double stops").tag("doubleStops")
        }
    }

    private var doubleStopPicker: some View {
        Picker("Pair", selection: Binding(
            get: { model.doubleStop.id },
            set: { id in
                if let pair = DoubleStops.all.first(where: { $0.id == id }) {
                    model.selectDoubleStop(pair)
                }
            }
        )) {
            ForEach(DoubleStops.all, id: \.id) { pair in
                Text(pair.label).tag(pair.id)
            }
        }
    }

    private var inversionPicker: some View {
        Picker("Inversion", selection: Binding(
            get: { model.selectedInversion ?? TriadsModuleModel.inversionOrder[0] },
            set: { model.selectInversion($0) }
        )) {
            ForEach(model.availableInversions, id: \.self) { inversion in
                Text(inversion).tag(inversion)
            }
        }
        .disabled(model.availableInversions.count < 2)
    }

    // MARK: Paths

    private var pathControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("String set") {
                stringSetPicker
                    .fixedSize(horizontal: true, vertical: false)
            }
            .disabled(isRunActive)
            LabeledContent("Mode") {
                modePicker
                    .fixedSize(horizontal: true, vertical: false)
            }
            .disabled(isRunActive)

            HStack(spacing: 12) {
                Button {
                    if isRunActive { model.stopEverything() } else { model.startProgression(loop: false) }
                } label: {
                    Label(isRunActive ? "Stop" : "Play path", systemImage: isRunActive ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(isRunActive ? .red : NotePalette.accent)
                .disabled(!isRunActive && (model.pathSteps.isEmpty || !state.isSamplePlaybackReady))

                Button {
                    model.startProgression(loop: true)
                } label: {
                    Label("Loop", systemImage: "repeat")
                }
                .buttonStyle(.glass)
                .disabled(isRunActive || model.pathSteps.isEmpty || !state.isSamplePlaybackReady)

                Button("Stop") { model.stopEverything() }
                    .buttonStyle(.glass)
                    .disabled(model.progressionSnapshot.status == .idle)
            }

            if model.progressionSnapshot.status != .idle {
                LabeledContent("Tempo") {
                    HStack(spacing: 12) {
                        Button { _ = model.slower() } label: { Image(systemName: "tortoise") }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Slower")
                        Text("\(model.progressionSnapshot.tempoBpm) bpm")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button { _ = model.faster() } label: { Image(systemName: "hare") }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Faster")
                    }
                }
            }

            if let beat = model.progressionSnapshot.countInBeat {
                Text("Count in… \(beat)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(NotePalette.accent)
            }
        }
    }

    private var stringSetPicker: some View {
        Picker("String set", selection: Binding(
            get: { model.pathStringSet },
            set: { model.selectPathStringSet($0) }
        )) {
            ForEach(TriadPaths.stringSets, id: \.self) { set in
                Text(set.rawValue).tag(set)
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { model.pathIsMajor },
            set: { model.setPathMajor($0) }
        )) {
            Text("Major").tag(true)
            Text("Minor").tag(false)
        }
    }

    // MARK: Explanation

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
        if model.isPathMode {
            return [
                "Every chord in the key, voiced on one set of three adjacent strings. The harmony moves; your hand does not leave the \(model.pathStringSet.rawValue) strings. That constraint is the exercise — it is how you learn to comp behind someone without hunting for shapes.",
                "The dots are coloured by what each note is doing — root, third, fifth — not by which note it is. The third is the one to watch: it alone decides whether a chord sounds major or minor.",
            ]
        }
        if model.view == .doubleStops {
            return [
                model.doubleStop.description,
                "Two notes instead of three. Drop the fifth and a triad still carries its character, because the third is doing the work — which is why double stops sit so well in a busy arrangement.",
            ]
        }
        return [
            model.triad.feel,
            "Three notes stacked in thirds: \(model.triad.degrees.joined(separator: ", ")). Every chord you play is this, thickened or rearranged. The dots are coloured by role rather than by pitch, so you can see the shape as degrees rather than as letters.",
            "An inversion is the same three notes with a different one in the bass. It is not a new chord — it is the same harmony sitting somewhere else under your hand.",
        ]
    }
}
