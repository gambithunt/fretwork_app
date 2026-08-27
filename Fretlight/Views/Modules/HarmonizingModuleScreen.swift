import SwiftUI

/// Harmonizing the scale — the chords of a key, and where they come from.
struct HarmonizingModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: HarmonizingModuleModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = state.makeHarmonizingModuleModel() }
            state.refreshSamplePlaybackReadiness()
        }
        .onDisappear { model?.stop() }
    }

    private func content(_ model: HarmonizingModuleModel) -> some View {
        ModuleLayout(module: .harmonizing) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleAudioNotice(isReady: state.isSamplePlaybackReady, error: state.samplePlaybackError)
                StandardTuningNotice(tuning: state.tuning, what: "These voicings")
                controls(model)
            }
        } stage: {
            FretboardBoardView(
                dots: model.dots,
                frets: model.highestFret,
                tuning: Tunings.standard,
                flipped: state.isFretboardFlipped,
                pulses: model.pulses
            )
            .frame(minHeight: 260)
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: HarmonizingModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("KEY")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(0..<12, id: \.self) { value in
                        rootButton(model, pitchClass: PitchClass(value))
                    }
                }
            }

            HStack(spacing: 12) {
                Picker("Mode", selection: Binding(
                    get: { model.isMajor },
                    set: { model.selectMajor($0) }
                )) {
                    Text("Major").tag(true)
                    Text("Minor").tag(false)
                }
                .fixedSize()

                Button {
                    model.strum()
                } label: {
                    Label("Play chord", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(NotePalette.accent)
                .disabled(model.voicing == nil)
                Button("Stop") { model.stop() }
            }

            // The degree row: the whole key at a glance, which is the point of
            // the module — you pick a degree and see what chord falls out.
            VStack(alignment: .leading, spacing: 6) {
                Text("DEGREE")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(model.chords.enumerated()), id: \.offset) { index, chord in
                        degreeButton(model, index: index, chord: chord)
                    }
                }
            }
        }
    }

    private func degreeButton(_ model: HarmonizingModuleModel, index: Int, chord: DiatonicChord) -> some View {
        let isActive = model.degree == index
        return Button {
            model.selectDegree(index)
        } label: {
            VStack(spacing: 2) {
                Text(chord.roman)
                    .font(.callout.weight(.semibold))
                Text(chord.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 58)
            .padding(.vertical, 6)
            .background(
                isActive ? NotePalette.accent.opacity(0.28) : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chord.roman), \(chord.name)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func rootButton(_ model: HarmonizingModuleModel, pitchClass: PitchClass) -> some View {
        let isActive = model.keyRoot == pitchClass
        let color = NotePalette.color(for: pitchClass)
        return Button {
            model.selectKeyRoot(pitchClass)
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

    private func readout(_ model: HarmonizingModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                ModuleStat(label: "Key", value: model.keyName, tint: NotePalette.color(for: .root))
                ModuleStat(label: "Chord", value: model.chord?.name ?? "—")
                ModuleStat(label: "Degree", value: model.chord?.roman ?? "—")
                ModuleStat(
                    label: "Stacked 3rds",
                    value: model.stackedTones.map { $0.name() }.joined(separator: " – ")
                )
            }
            ModuleProse(paragraphs: prose(model))
        }
    }

    private func prose(_ model: HarmonizingModuleModel) -> [String] {
        guard let chord = model.chord else { return [] }
        let tones = model.stackedTones.map { $0.name() }.joined(separator: ", ")
        return [
            "Take the \(ordinal(model.degree + 1)) note of \(model.keyName), then the note two above it, then two above that: \(tones). Stack those and you have \(chord.name) — the \(chord.roman) chord of the key.",
            "Nobody decided \(chord.roman) should be \(qualityWord(chord.quality)). It falls out of the spacing: the scale's own gaps put a \(qualityWord(chord.quality) == "major" ? "major" : "minor or flattened") 3rd above that degree, and the chord's quality follows. Step through the degrees and the same pattern of qualities appears in every key.",
            "That pattern is why a progression written as \(model.isMajor ? "I–V–vi–IV" : "i–VI–III–VII") works in any key you like — the roman numerals name the *degrees*, and the chords come out of whichever key you point them at."
        ]
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
