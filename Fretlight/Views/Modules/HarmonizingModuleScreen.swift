import SwiftUI

/// Harmonizing the scale — the chords of a key, and where they come from.
struct HarmonizingModuleScreen: View {
    @Bindable var state: AppState
    @State private var model: HarmonizingModuleModel?
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
            VStack(alignment: .trailing, spacing: 8) {
                FretRangeToggle(isExpanded: $showsFullNeck, defaultFrets: model.highestFret)
                FretboardBoardView(
                    dots: model.dots,
                    frets: showsFullNeck ? 22 : model.highestFret,
                    tuning: Tunings.standard,
                    flipped: state.isFretboardFlipped,
                    pulses: model.pulses
                )
                .frame(minHeight: 260)
            }
        } readout: {
            readout(model)
        }
    }

    private func controls(_ model: HarmonizingModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PitchClassPicker(title: "KEY", selection: model.keyRoot, onSelect: model.selectKeyRoot)
                .moduleNotesCard()

            VStack(alignment: .leading, spacing: 12) {
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

                // The degree row: the whole key at a glance, which is the
                // point of the module — you pick a degree and see what chord
                // falls out.
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEGREE")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    ChipPicker(
                        values: Array(model.chords.indices),
                        selection: model.degree,
                        tint: { _ in NotePalette.accent },
                        onSelect: model.selectDegree,
                        accessibilityLabel: { "\(model.chords[$0].roman), \(model.chords[$0].name)" }
                    ) { index, isActive in
                        VStack(spacing: 2) {
                            Text(model.chords[index].roman)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(isActive ? .black : .primary)
                            Text(model.chords[index].name)
                                .font(.caption2)
                                .foregroundStyle(isActive ? .black.opacity(0.65) : .secondary)
                        }
                    }
                }
            }
            .moduleOptionsCard()
        }
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
