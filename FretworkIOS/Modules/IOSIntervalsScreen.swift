import SwiftUI

/// The Intervals module on iOS, built entirely on the shared
/// `IOSModuleScaffold` (D-11/D-18): ‹ › step through the intervals, tapping a
/// root on the board re-anchors the shape under a different finger, and the
/// drawer holds the root, label mode, Play, the interval's uses and the
/// explanation.
struct IOSIntervalsScreen: View {
    @Bindable var state: AppState

    @State private var model: IntervalsModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSIntervalsStage(state: state, model: model)
            } else {
                Color.clear
                    .task {
                        if model == nil {
                            model = state.makeIntervalsModuleModel()
                            state.refreshSamplePlaybackReadiness()
                        }
                    }
            }
        }
        .background(NotePalette.backdrop)
    }
}

private struct IOSIntervalsStage: View {
    let state: AppState
    let model: IntervalsModuleModel
    @State private var labelMode: FretboardLabelMode = .degrees

    /// iPad draws the full 22-fret neck; the phone keeps the module's range.
    private var boardFrets: Int {
        IOSModuleBoard.frets(idiom: UIDevice.current.userInterfaceIdiom, moduleFrets: model.highestFret)
    }

    private var dots: [FretboardDot] {
        labelMode == .notes
            ? model.dots.showingNoteNames(in: model.tuning)
            : model.dots.map { dot in
                var numbered = dot
                if dot.id.hasPrefix("root") { numbered.label = "1" }
                return numbered
            }
    }

    private var isPrevDisabled: Bool {
        guard let index = Intervals.all.firstIndex(of: model.interval) else { return true }
        return index == 0
    }

    private var isNextDisabled: Bool {
        guard let index = Intervals.all.firstIndex(of: model.interval) else { return true }
        return index == Intervals.all.count - 1
    }

    var body: some View {
        IOSModuleScaffold(
            title: IOSModuleScreenTitle.title(for: .intervals),
            subtitle: IOSModuleLandscapeFormat.intervalSubtitle(model.interval),
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
                    onHit: { hit in
                        let position = Self.position(of: hit)
                        model.selectAnchor(string: position.string, fret: position.fret)
                    }
                )
            },
            leadingAction: .step(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous interval",
                disabled: isPrevDisabled,
                action: { withAnimation(FretworkMotion.gravity) { model.selectInterval(Self.shiftedInterval(from: model.interval, by: -1)) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Next interval",
                disabled: isNextDisabled,
                action: { withAnimation(FretworkMotion.gravity) { model.selectInterval(Self.shiftedInterval(from: model.interval, by: 1)) } }
            ),
            primaryAction: .primary(
                title: "Play interval",
                accessibilityLabel: "Play interval",
                disabled: model.practicalTarget == nil || !state.isSamplePlaybackReady,
                action: { model.playInterval() }
            ),
            drawerTitle: "Interval & key",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSIntervalsDrawer(state: state, model: model, labelMode: $labelMode)
            },
            isRunActive: false,
            guidedRunStepText: "",
            onTuningChange: { model.retune(to: $0) },
            frets: boardFrets,
            focusFret: IOSModulePortraitStrip.focusFret(for: dots, highestFret: boardFrets)
        )
        .onDisappear { model.stop() }
    }

    private static func shiftedInterval(from current: Interval, by delta: Int) -> Interval {
        let all = Intervals.all
        guard let index = all.firstIndex(of: current) else { return current }
        return all[((index + delta) % all.count + all.count) % all.count]
    }

    private static func position(of hit: FretboardHit) -> FretPosition {
        switch hit {
        case .dot(let dot): dot.position
        case .cell(let position): position
        }
    }
}

// MARK: - Drawer

private struct IOSIntervalsDrawer: View {
    let state: AppState
    let model: IntervalsModuleModel
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
                    Picker("Labels", selection: $labelMode) {
                        Text("Notes").tag(FretboardLabelMode.notes)
                        Text("Numbers").tag(FretboardLabelMode.degrees)
                    }
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                }

                IOSModulePlaybackNotice(state: state)

                uses
                explanation
            }
            .padding(20)
        }
    }

    /// What the interval is *for*. Each use is colour-coded by category,
    /// which is a separate scale from the note colours — the web keeps
    /// `--fw-use-*` apart from the note hues for exactly this reason.
    private var uses: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Used for")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(Array(model.interval.uses.enumerated()), id: \.offset) { index, use in
                    let tint = Self.color(for: use.category)
                    Button {
                        model.selectedUseIndex = model.selectedUseIndex == index ? nil : index
                    } label: {
                        Text(use.label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tint.opacity(model.selectedUseIndex == index ? 0.4 : 0.16), in: Capsule())
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.selectedUseIndex == index ? [.isSelected] : [])
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            Text(model.interval.feel)
            Text(model.exercise)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static func color(for category: IntervalUseCategory) -> Color {
        // The web's `--fw-use-*` values.
        switch category {
        case .chords: Color(hex: 0xe07b5f)
        case .melody: Color(hex: 0x5b9de1)
        case .riffs: Color(hex: 0xd7b84b)
        case .tension: Color(hex: 0x9a8be8)
        }
    }
}
