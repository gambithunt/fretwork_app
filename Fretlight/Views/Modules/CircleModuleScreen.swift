import SwiftUI

/// The circle of fifths — the one module whose stage is not a fretboard.
struct CircleModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: CircleModuleModel?
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
            if model == nil { model = state.makeCircleModuleModel() }
            state.refreshSamplePlaybackReadiness()
        }
        .onChange(of: state.tuning) { _, tuning in model?.retune(to: tuning) }
        .onDisappear { model?.stop() }
    }

    private func content(_ model: CircleModuleModel) -> some View {
        ModuleLayout(module: .circle) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                controls(model)
            }
        } stage: {
            HStack(alignment: .top, spacing: 32) {
                ring(model)
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        Text("Tonic triad")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: 12)
                    }
                    FretboardBoardView(
                        dots: model.dots,
                        frets: showsFullNeck ? 22 : 12,
                        tuning: model.tuning,
                        flipped: state.isFretboardFlipped,
                        pulses: model.pulses
                    )
                    .frame(minHeight: 200)
                }
            }
        } readout: {
            readout(model)
        }
    }

    /// The ring itself. Drawn rather than laid out, because the arrangement —
    /// each step clockwise a fifth up — *is* the content.
    private func ring(_ model: CircleModuleModel) -> some View {
        let size: CGFloat = 320
        let centre = size / 2
        let majorRadius: CGFloat = 128
        let minorRadius: CGFloat = 84

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: majorRadius * 2 + 44, height: majorRadius * 2 + 44)

            ForEach(Array(model.keys.enumerated()), id: \.offset) { index, key in
                let role = model.role(at: index)
                let angle = Angle(degrees: CircleModuleModel.angle(forIndex: index))

                // Major key, outer ring.
                keyButton(model, key: key, role: role, isMinor: false)
                    .offset(
                        x: majorRadius * CGFloat(sin(angle.radians)),
                        y: -majorRadius * CGFloat(cos(angle.radians))
                    )

                // Its relative minor, inner ring — the same seven notes with a
                // different home, which is why they sit on the same spoke.
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

    private func keyButton(_ model: CircleModuleModel, key: PitchClass, role: CircleModuleModel.Role, isMinor: Bool) -> some View {
        let isTonic = role == .tonic
        let fill = model.color(for: role)
        return Button {
            withAnimation(FretworkMotion.gravity) { model.select(key) }
        } label: {
            Text(key.name())
                .font(.callout.weight(role == .none ? .regular : .semibold))
                .foregroundStyle(role == .none ? Color.white.opacity(0.75) : .black)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(fill.opacity(0.82))
                        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                )
                // A colour-matched glow instead of the old hard white ring —
                // the tonic still reads instantly across the ring, just as
                // light rather than as an outline.
                .shadow(color: fill.opacity(isTonic ? 0.75 : 0), radius: isTonic ? 10 : 0)
                .scaleEffect(isTonic ? 1.06 : 1)
        }
        .buttonStyle(ElasticPressStyle())
        .accessibilityLabel("\(key.name()) major")
        .accessibilityValue(roleName(role))
        .accessibilityAddTraits(isTonic ? [.isSelected] : [])
    }

    private func roleName(_ role: CircleModuleModel.Role) -> String {
        switch role {
        case .tonic: "the key"
        case .dominant: "a fifth up"
        case .subdominant: "a fifth down"
        case .none: ""
        }
    }

    // Circle has no root/key chip picker — the ring itself, in `stage`, is
    // that selector — so this is one options card rather than the
    // notes-card-plus-options-card split every other module uses.
    private func controls(_ model: CircleModuleModel) -> some View {
        HStack(spacing: 12) {
            Button { model.step(by: -1) } label: { Label("Anticlockwise", systemImage: "arrow.counterclockwise") }
            Button { model.step(by: 1) } label: { Label("Clockwise", systemImage: "arrow.clockwise") }
            Button {
                model.strum()
            } label: {
                Label("Play tonic", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(NotePalette.accent)
            .disabled(model.dots.isEmpty)
            Button("Stop") { model.stop() }
        }
        .moduleOptionsCard()
    }

    private func readout(_ model: CircleModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(label: "Key", value: "\(model.selected.name()) major",
                           tint: NotePalette.color(for: .root))
                ModuleStat(label: "Relative minor", value: "\(model.relativeMinor.name()) minor")
                ModuleStat(label: "A fifth up", value: model.dominant.name(),
                           tint: NotePalette.color(for: .fifth))
                ModuleStat(label: "A fifth down", value: model.subdominant.name(),
                           tint: NotePalette.color(for: .degree))
            }
            ModuleProse(paragraphs: prose(model))
        }
    }

    private func prose(_ model: CircleModuleModel) -> [String] {
        let shared = model.sharedNoteCount(with: model.dominant)
        let opposite = model.keys[(model.selectedIndex + 6) % 12]
        return [
            "Each step clockwise is a fifth up. That is not a filing system — it is why the keys beside yours are the ones you can move to freely: \(model.selected.name()) and \(model.dominant.name()) share \(shared) of their seven notes, so only one note has to change.",
            "\(model.subdominant.name()) and \(model.dominant.name()) sitting either side of \(model.selected.name()) is the same fact that makes I–IV–V the backbone of so many songs. The three chords are neighbours on this ring.",
            "Directly opposite is \(opposite.name()), sharing only \(model.sharedNoteCount(with: opposite)) notes with \(model.selected.name()) — the furthest you can get from home. The inner ring shows each key's relative minor: the same seven notes, started somewhere else."
        ]
    }
}
