import SwiftUI

/// The Pentatonic module on iOS.
///
/// Portrait reuses the Mac `PentatonicModuleScreen` verbatim (D-18).
/// Landscape is the M2 arrangement (D-20/D-22): ‹ › step through boxes 1–5,
/// and the drawer holds root, quality, show and the practise button. During a
/// guided run the bottom band switches to ■ Stop + the current step (D-27),
/// so the drawer cannot be opened mid-exercise.
struct IOSPentatonicScreen: View {
    @Bindable var state: AppState

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var landscapeModel: PentatonicModuleModel?

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                if let model = landscapeModel {
                    IOSPentatonicLandscape(state: state, model: model)
                } else {
                    Color.clear
                        .task {
                            if landscapeModel == nil {
                                landscapeModel = state.makePentatonicModuleModel()
                                state.refreshSamplePlaybackReadiness()
                            }
                        }
                }
            } else {
                PentatonicModuleScreen(state: state)
            }
        }
        .background(NotePalette.backdrop)
    }
}

// MARK: - Landscape (M2)

private struct IOSPentatonicLandscape: View {
    let state: AppState
    let model: PentatonicModuleModel

    private var subtitle: String {
        IOSModuleLandscapeFormat.pentatonicSubtitle(
            root: model.rootPitchClass,
            quality: model.quality,
            box: model.focusPosition
        )
    }

    private var bandMode: IOSModuleBandMode {
        IOSSnapshot.guidedRunActive || model.guidedSnapshot.status != .idle
            ? .guidedRun
            : .normal
    }

    private var guidedStepText: String {
        guard let next = model.nextStep ?? model.box.first else { return "" }
        return IOSModuleLandscapeFormat.guidedRunStepText(next: next)
    }

    var body: some View {
        IOSModuleLandscapeScaffold(
            title: IOSModuleScreenTitle.title(for: .pentatonic),
            subtitle: subtitle,
            tuning: Tunings.standard,
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
                disabled: model.position == 0,
                action: { withAnimation(FretworkMotion.gravity) { model.selectPosition(model.position - 1) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Next box",
                disabled: model.position == 4,
                action: { withAnimation(FretworkMotion.gravity) { model.selectPosition(model.position + 1) } }
            ),
            drawerTitle: "Scale & key",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSPentatonicDrawer(state: state, model: model)
            },
            bandMode: bandMode,
            guidedRunStepText: guidedStepText,
            onStopGuidedRun: { model.stopGuided() }
        )
        .onDisappear { model.stop() }
    }
}

// MARK: - Drawer

private struct IOSPentatonicDrawer: View {
    let state: AppState
    let model: PentatonicModuleModel

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
                        LabeledContent("Show") {
                            showPicker
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

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
                model.startGuided()
            } label: {
                Label("Practise", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(NotePalette.accent)
            .disabled(model.box.isEmpty || !state.isSamplePlaybackReady)
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
