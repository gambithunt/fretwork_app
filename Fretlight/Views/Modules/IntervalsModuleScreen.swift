import SwiftUI

/// Intervals — the distance between two notes, shown as a shape under the hand.
///
/// See `IntervalsModuleModel` for the rules; this is their presentation.
struct IntervalsModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: IntervalsModuleModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = state.makeIntervalsModuleModel() }
        }
        .onChange(of: state.tuning) { _, tuning in model?.retune(to: tuning) }
        .onDisappear { model?.stop() }
    }

    private func content(_ model: IntervalsModuleModel) -> some View {
        ModuleLayout(module: .intervals) {
            controls(model)
        } stage: {
            FretboardBoardView(
                dots: model.dots,
                frets: model.highestFret,
                tuning: model.tuning,
                flipped: state.isFretboardFlipped,
                pulses: model.pulses,
                // Tapping a root re-anchors the same interval under a different
                // finger, which is the module's main interaction.
                onHit: { hit in
                    let position = Self.position(of: hit)
                    model.selectAnchor(string: position.string, fret: position.fret)
                }
            )
            .frame(minHeight: 260)
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: IntervalsModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ROOT")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(0..<12, id: \.self) { value in
                        rootButton(model, pitchClass: PitchClass(value))
                    }
                }
            }

            HStack(spacing: 16) {
                Picker("Interval", selection: Binding(
                    get: { model.interval.short },
                    set: { short in
                        if let interval = Intervals.all.first(where: { $0.short == short }) {
                            model.selectInterval(interval)
                        }
                    }
                )) {
                    ForEach(Intervals.all, id: \.short) { interval in
                        Text("\(interval.name) (\(interval.short))").tag(interval.short)
                    }
                }
                .fixedSize()

                Button {
                    model.playInterval()
                } label: {
                    Label("Play interval", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(NotePalette.accent)
                .disabled(model.practicalTarget == nil)

                Button("Stop") { model.stop() }
            }
        }
    }

    private func rootButton(_ model: IntervalsModuleModel, pitchClass: PitchClass) -> some View {
        let isActive = model.rootPitchClass == pitchClass
        let color = NotePalette.color(for: pitchClass)
        return Button {
            model.selectRoot(pitchClass)
        } label: {
            Text(pitchClass.name())
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isActive ? color : color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(isActive ? Color.black : color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pitchClass.name())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func readout(_ model: IntervalsModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(
                    label: "Interval",
                    value: "\(model.rootPitchClass.name()) → \(model.targetPitchClass.name())",
                    tint: NotePalette.color(for: .third)
                )
                ModuleStat(label: "Distance", value: "\(model.interval.semitones) semitones")
                ModuleStat(label: "Anchors", value: "\(model.playableAnchors.count)")
            }

            uses(model)
            ModuleProse(paragraphs: [model.interval.feel, model.exercise])
        }
    }

    /// What the interval is *for*. Each use is colour-coded by category, which
    /// is a separate scale from the note colours — the web keeps
    /// `--fw-use-*` apart from the note hues for exactly this reason.
    private func uses(_ model: IntervalsModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USED FOR")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
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
                            .background(tint.opacity(model.selectedUseIndex == index ? 0.4 : 0.16),
                                        in: Capsule())
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .help(Self.categoryLabel(use.category))
                }
            }
        }
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

    private static func categoryLabel(_ category: IntervalUseCategory) -> String {
        switch category {
        case .chords: "Chord"
        case .melody: "Melody"
        case .riffs: "Riff"
        case .tension: "Tension"
        }
    }

    private static func position(of hit: FretboardHit) -> FretPosition {
        switch hit {
        case .dot(let dot): dot.position
        case .cell(let position): position
        }
    }
}
