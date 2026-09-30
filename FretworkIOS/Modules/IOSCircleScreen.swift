import SwiftUI

/// The Circle of fifths module on iOS.
///
/// Portrait reuses the Mac `CircleModuleScreen` verbatim (D-18). Landscape is
/// the one non-fretboard stage (D-28): the ring on the left, a small board
/// with the selected key's tonic triad on the right, and ‹ › turning the
/// circle. The drawer holds the label mode, Play tonic and the explanation.
struct IOSCircleScreen: View {
    @Bindable var state: AppState

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var landscapeModel: CircleModuleModel?

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                if let model = landscapeModel {
                    IOSCircleLandscape(state: state, model: model)
                } else {
                    Color.clear
                        .task {
                            if landscapeModel == nil {
                                landscapeModel = state.makeCircleModuleModel()
                                state.refreshSamplePlaybackReadiness()
                            }
                        }
                }
            } else {
                CircleModuleScreen(state: state)
            }
        }
        .background(NotePalette.backdrop)
    }
}

// MARK: - Landscape (M2)

private struct IOSCircleLandscape: View {
    let state: AppState
    let model: CircleModuleModel
    @State private var labelMode: FretboardLabelMode = .notes

    private var dots: [FretboardDot] {
        let triadDegrees = [
            model.selected: "1",
            model.selected.transposed(by: 4): "3",
            model.selected.transposed(by: 7): "5"
        ]
        return labelMode == .notes
            ? model.dots
            : model.dots.map { dot in
                var numbered = dot
                if let pitchClass = dot.pitchClass(in: model.tuning) {
                    numbered.label = triadDegrees[pitchClass] ?? dot.label
                }
                return numbered
            }
    }

    var body: some View {
        IOSModuleLandscapeScaffold(
            title: IOSModuleScreenTitle.title(for: .circle),
            subtitle: IOSModuleLandscapeFormat.circleSubtitle(model.selected),
            tuning: model.tuning,
            isFixedShapeModule: false,
            state: state,
            neck: { stage },
            leadingAction: .step(
                systemImage: "chevron.left",
                accessibilityLabel: "Anticlockwise",
                disabled: false,
                action: { withAnimation(FretworkMotion.gravity) { model.step(by: -1) } }
            ),
            trailingAction: .step(
                systemImage: "chevron.right",
                accessibilityLabel: "Clockwise",
                disabled: false,
                action: { withAnimation(FretworkMotion.gravity) { model.step(by: 1) } }
            ),
            drawerTitle: "Key & labels",
            drawerSystemImage: "slider.horizontal.3",
            drawer: {
                IOSCircleDrawer(state: state, model: model, labelMode: $labelMode)
            },
            bandMode: .normal,
            guidedRunStepText: "",
            onStopGuidedRun: {},
            onTuningChange: { model.retune(to: $0) }
        )
        .onDisappear { model.stop() }
    }

    private var stage: some View {
        HStack(alignment: .center, spacing: 20) {
            circleRing(model, size: 200)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tonic triad")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                FretboardBoardView(
                    dots: dots,
                    frets: 12,
                    tuning: model.tuning,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
            }
            .frame(maxWidth: 400, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The ring, drawn rather than laid out — the arrangement (each step
    /// clockwise a fifth up) *is* the content. Compact-ified from the Mac's
    /// `CircleModuleScreen.ring` for landscape height.
    private func circleRing(_ model: CircleModuleModel, size: CGFloat) -> some View {
        let majorRadius = size * 0.42
        let minorRadius = size * 0.27
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: majorRadius * 2 + 40, height: majorRadius * 2 + 40)

            ForEach(Array(model.keys.enumerated()), id: \.offset) { index, key in
                let role = model.role(at: index)
                let angle = Angle(degrees: CircleModuleModel.angle(forIndex: index))

                circleKeyButton(model, key: key, role: role)
                    .offset(
                        x: majorRadius * CGFloat(sin(angle.radians)),
                        y: -majorRadius * CGFloat(cos(angle.radians))
                    )

                Text(key.transposed(by: 9).name().lowercased() + "m")
                    .font(.caption2)
                    .foregroundStyle(role == .tonic ? NotePalette.color(for: .root) : .secondary)
                    .offset(
                        x: minorRadius * CGFloat(sin(angle.radians)),
                        y: -minorRadius * CGFloat(cos(angle.radians))
                    )
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Circle of fifths, \(model.selected.name()) selected")
    }

    private func circleKeyButton(_ model: CircleModuleModel, key: PitchClass, role: CircleModuleModel.Role) -> some View {
        let isTonic = role == .tonic
        let fill = model.color(for: role)
        return Button {
            withAnimation(FretworkMotion.gravity) { model.select(key) }
        } label: {
            Text(key.name())
                .font(.callout.weight(role == .none ? .regular : .semibold))
                .foregroundStyle(role == .none ? Color.white.opacity(0.75) : .black)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(fill.opacity(0.82))
                        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                )
                .shadow(color: fill.opacity(isTonic ? 0.75 : 0), radius: isTonic ? 10 : 0)
                .scaleEffect(isTonic ? 1.06 : 1)
        }
        .buttonStyle(ElasticPressStyle())
        .accessibilityLabel("\(key.name()) major")
        .accessibilityAddTraits(isTonic ? [.isSelected] : [])
    }
}

// MARK: - Drawer

private struct IOSCircleDrawer: View {
    let state: AppState
    let model: CircleModuleModel
    @Binding var labelMode: FretboardLabelMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LabeledContent("Labels") {
                    Picker("Labels", selection: $labelMode) {
                        Text("Notes").tag(FretboardLabelMode.notes)
                        Text("Numbers").tag(FretboardLabelMode.degrees)
                    }
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Play")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Button {
                            model.strum()
                        } label: {
                            Label("Play tonic", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(NotePalette.accent)
                        .disabled(model.dots.isEmpty || !state.isSamplePlaybackReady)

                        Button("Stop") { model.stop() }
                            .buttonStyle(.glass)
                    }
                    IOSModulePlaybackNotice(state: state)
                }

                explanation
            }
            .padding(20)
        }
    }

    private var explanation: some View {
        let shared = model.sharedNoteCount(with: model.dominant)
        let opposite = model.keys[(model.selectedIndex + 6) % 12]
        return VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            Text("Each step clockwise is a fifth up. \(model.selected.name()) and \(model.dominant.name()) share \(shared) of their seven notes, so only one note has to change.")
            Text("Directly opposite is \(opposite.name()), sharing only \(model.sharedNoteCount(with: opposite)) notes — the furthest you can get from home. The inner ring shows each key's relative minor: the same seven notes, started somewhere else.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
