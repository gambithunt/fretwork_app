import SwiftUI

/// The Pentatonic module on iOS, built entirely on the shared
/// `IOSModuleScaffold` (D-11/D-18): ‹ › step through boxes 1–5 and the drawer
/// holds root, quality, show and the practise button. During a guided run the
/// bottom band switches to ■ Stop + the current step (D-27).
struct IOSPentatonicScreen: View {
    @Bindable var state: AppState

    @State private var model: PentatonicModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSPentatonicStage(state: state, model: model)
            } else {
                Color.clear
                    .task {
                        if model == nil {
                            model = state.makePentatonicModuleModel()
                            state.refreshSamplePlaybackReadiness()
                            #if DEBUG
                            // Drive a real session for the guided-run
                            // screenshot, so the board's current-step
                            // emphasis and the next-step subtitle come from the
                            // same run rather than a view-only flag.
                            if IOSSnapshot.guidedRunActive {
                                model?.startGuided()
                            }
                            #endif
                        }
                    }
            }
        }
        .background(NotePalette.backdrop)
    }
}

private struct IOSPentatonicStage: View {
    let state: AppState
    let model: PentatonicModuleModel

    private var subtitle: String {
        IOSModuleLandscapeFormat.pentatonicSubtitle(
            root: model.rootPitchClass,
            quality: model.quality,
            box: model.focusPosition
        )
    }

    private var isRunActive: Bool {
        model.guidedSnapshot.status != .idle
    }

    private var guidedStepText: String {
        guard isRunActive, let next = model.nextStep ?? model.box.first else { return "" }
        return IOSModuleLandscapeFormat.guidedRunStepText(next: next)
    }

    var body: some View {
        IOSModuleScaffold(
            title: IOSModuleScreenTitle.title(for: .pentatonic),
            subtitle: subtitle,
            tuning: state.tuning,
            boardTuning: Tunings.standard,
            isFixedShapeModule: true,
            state: state,
            neck: {
                FretboardBoardView(
                    dots: model.dots,
                    frets: model.highestFret,
                    tuning: Tunings.standard,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
            },
            leadingAction: .step(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous box",
                disabled: isRunActive || model.position == 0,
                action: { withAnimation(FretworkMotion.gravity) { model.selectPosition(model.position - 1) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Next box",
                disabled: isRunActive || model.position == 4,
                action: { withAnimation(FretworkMotion.gravity) { model.selectPosition(model.position + 1) } }
            ),
            drawerTitle: "Scale & key",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSPentatonicDrawer(state: state, model: model, isRunActive: isRunActive)
            },
            isRunActive: isRunActive,
            guidedRunStepText: guidedStepText,
            frets: model.highestFret,
            focusFret: IOSModulePortraitStrip.focusFret(for: model.dots, highestFret: model.highestFret)
        )
        .onDisappear { model.stop() }
    }
}

// MARK: - Drawer

private struct IOSPentatonicDrawer: View {
    let state: AppState
    let model: PentatonicModuleModel
    let isRunActive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PitchClassPicker(
                    title: "Root",
                    selection: model.rootPitchClass,
                    onSelect: model.selectRoot
                )
                .disabled(isRunActive)
                .iosRunDimmed(isRunActive)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Scale")
                        .font(.headline)
                    VStack(spacing: 12) {
                        LabeledContent("Quality") {
                            qualityPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        LabeledContent("Show") {
                            showPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .disabled(isRunActive)

                practise

                IOSModulePlaybackNotice(state: state)
            }
            .padding(20)
        }
    }

    private var practise: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practise")
                .font(.headline)
            Button {
                if isRunActive { model.stopGuided() } else { model.startGuided() }
            } label: {
                Label(isRunActive ? "Stop" : "Practise", systemImage: isRunActive ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(isRunActive ? .red : NotePalette.accent)
            .disabled(!isRunActive && (model.box.isEmpty || !state.isSamplePlaybackReady))
            Text("A four-beat count-in, then one note per beat up the box. Tempo can be changed while practising.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var qualityPicker: some View {
        Picker("Quality", selection: Binding(
            get: { model.quality },
            set: { model.selectQuality($0) }
        )) {
            Text("Minor").tag(PentatonicQuality.minorPentatonic)
            Text("Major").tag(PentatonicQuality.majorPentatonic)
        }
        .pickerStyle(.menu)
    }

    private var showPicker: some View {
        Picker("Show", selection: Binding(
            get: { model.displayMode },
            set: { model.selectDisplayMode($0) }
        )) {
            Text("One box").tag(PentatonicModuleModel.DisplayMode.single)
            Text("Pair").tag(PentatonicModuleModel.DisplayMode.pair)
            Text("Path").tag(PentatonicModuleModel.DisplayMode.path)
        }
        .pickerStyle(.menu)
    }
}
