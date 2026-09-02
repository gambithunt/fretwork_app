import SwiftUI

/// The two useful ways to read a contextual fretboard: the note's literal
/// name, or the job it performs inside the exercise's current harmony.
enum FretboardLabelMode: String, CaseIterable {
    case notes
    case degrees
}

/// Shared compact selector used in each learning screen's options card.
struct FretboardLabelPicker: View {
    @Binding var selection: FretboardLabelMode

    var body: some View {
        Picker("Labels", selection: $selection) {
            Text("Notes").tag(FretboardLabelMode.notes)
            Text("Numbers").tag(FretboardLabelMode.degrees)
        }
        .fixedSize()
        .help("Show note names or the degrees used by this lesson")
    }
}

extension Array where Element == FretboardDot {
    /// The models retain their degree/interval labels as their teaching
    /// source. This presentation-only transform swaps only labelled dots to
    /// their real pitch names, so deliberately blank context dots stay quiet.
    func showingNoteNames(in tuning: Tuning) -> Self {
        map { dot in
            guard !dot.label.isEmpty, let pitchClass = dot.pitchClass(in: tuning) else { return dot }
            var named = dot
            named.label = pitchClass.name()
            return named
        }
    }
}

/// The frame every learning module renders into, so layout lives in one place.
///
/// The Swift counterpart of `../fretwork/src/lib/components/ModuleLayout.svelte`
/// and its three zones:
///
/// - **controls** — the module's selectors and its play button
/// - **stage** — the hero, almost always the fretboard
/// - **readout** — stats and the theory copy explaining what is on the board
///
/// The web's responsive rules do not come across: they exist because that app
/// is used on a tablet in portrait with a guitar in the way. This is a Mac
/// window with a floor of 950 x 800, so the desktop arrangement is the only
/// arrangement — controls in a wrapping bar, stage full width, readout beneath.
///
/// `../fretwork/AGENTS.md` prescribes this skeleton for every module, and
/// workstream 006's first verified finding is that the Swift equivalent should
/// exist *before* the second module rather than after the fifth.
struct ModuleLayout<Controls: View, Stage: View, Readout: View>: View {
    let module: LearningModule
    let state: AppState
    @ViewBuilder var controls: Controls
    @ViewBuilder var stage: Stage
    @ViewBuilder var readout: Readout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // `controls` now draws its own cards internally — a fixed-size
                // one around the module's note/key picker (`.moduleNotesCard()`)
                // and a second below it for everything else
                // (`.moduleOptionsCard()`), so the note picker holds the same
                // position and size across every module rather than resizing
                // around whatever secondary controls that module happens to
                // have. `readout` still gets one card of its own — the stage
                // keeps its own look (`BoardCanvas` already draws its
                // instrument-body card).
                controls
                stage
                readout
                    // The readout is the interpretation of the full-width
                    // fretboard, not a small sidebar beneath it. Give it the
                    // same horizontal claim as the board and enough room for
                    // its larger teaching type to breathe.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .glassCard()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NotePalette.backdrop)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(module.title)
                    .font(.largeTitle.weight(.semibold))
                Text(module.blurb)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if state.showsLiveNoteOnModules {
                ModuleLiveNoteReadout(state: state)
            }
        }
    }
}

/// The live Listen readout distilled to its one useful practising cue. This
/// leaf owns the audio-rate `display` read so changing notes does not
/// invalidate the rest of a module's controls, board, or teaching copy.
private struct ModuleLiveNoteReadout: View {
    let state: AppState

    var body: some View {
        let display = state.display
        let noteColor = display.note.map { NotePalette.color(for: $0.name) }

        VStack(spacing: 4) {
            Text("LISTENING")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)

            Text(display.note.map { "\($0.name)\($0.octave)" } ?? "—")
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .frame(minWidth: 104)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(noteColor?.opacity(0.28) ?? .white.opacity(0.08))
                        .overlay {
                            Capsule()
                                .stroke(noteColor?.opacity(0.52) ?? .white.opacity(0.10), lineWidth: 1)
                        }
                        .shadow(color: noteColor?.opacity(0.26) ?? .clear, radius: 12)
                }
        }
        .animation(.easeInOut(duration: 0.2), value: display.note?.midiNote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.note.map { "Live note \($0.name)\($0.octave)" } ?? "Listening for a note")
    }
}

/// Draws only the live-note feedback layer over a lesson fretboard. Keeping
/// this separate from `FretboardBoardView` means a pitch update redraws this
/// small set of halos, not the board's dots, controls, or teaching copy.
private struct ModuleLiveNoteGlow: View {
    let state: AppState
    let dots: [FretboardDot]
    let frets: Int
    let tuning: Tuning
    let flipped: Bool
    var margins: BoardGeometry.Margins = .labelled

    @ViewBuilder var body: some View {
        // Do not read `display` while the feature is off. Besides making the
        // feature genuinely inert, that removes this view's audio-rate
        // dependency until the player opts in.
        if state.showsLiveNoteOnModules, state.highlightsLiveNoteOnFretboards {
            activeGlow
        }
    }

    private var activeGlow: some View {
        // Keep the layer present while silence arrives so the matching rings
        // leave with the requested brief fade instead of disappearing as a
        // whole overlay in one transaction.
        let note = state.display.note
        return GeometryReader { proxy in
            let geometry = BoardGeometry(
                size: proxy.size,
                frets: frets,
                strings: tuning.openMIDINotes.count,
                flipped: flipped,
                margins: margins
            )
            ZStack {
                if let note {
                    let matchingDots = Self.matching(dots, pitchClass: PitchClass(note.midiNote), tuning: tuning)
                    let color = NotePalette.color(for: note.name)
                    ForEach(matchingDots) { dot in
                        Circle()
                            .strokeBorder(color.opacity(0.72 * dot.alpha), lineWidth: 2)
                            .frame(width: dot.radius * 2 + 8, height: dot.radius * 2 + 8)
                            .shadow(color: color.opacity(0.78 * dot.alpha), radius: 9)
                            .position(geometry.point(dot.position))
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: note?.midiNote)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func matching(_ dots: [FretboardDot], pitchClass: PitchClass, tuning: Tuning) -> [FretboardDot] {
        dots.filter { $0.pitchClass(in: tuning) == pitchClass }
    }
}

extension View {
    /// Adds live-note feedback to a lesson board without handing the board an
    /// audio-rate dependency. The active dot model stays the sole authority
    /// on which lesson positions are visible; this layer merely decorates the
    /// visible positions that match the detected pitch class.
    func moduleLiveNoteGlow(
        state: AppState,
        dots: [FretboardDot],
        frets: Int,
        tuning: Tuning,
        flipped: Bool,
        margins: BoardGeometry.Margins = .labelled
    ) -> some View {
        overlay {
            ModuleLiveNoteGlow(
                state: state,
                dots: dots,
                frets: frets,
                tuning: tuning,
                flipped: flipped,
                margins: margins
            )
        }
    }
}

/// A labelled row of mutually exclusive choices — the shape the web gets from
/// `ButtonGroup`.
///
/// The web uses buttons rather than a dropdown because that app is driven by
/// touch with a guitar in your hands, and workstream 006 records explicitly that
/// this is a product constraint which *does not transfer*. So this is a real
/// macOS `Picker`, in menu style.
///
/// Never `.pickerStyle(.segmented)`: `CLAUDE.md` records a measured leak of
/// ~1800 `ObservationRegistrar` contexts per 30 s when a segmented picker is
/// rebuilt at audio rate. Modules do not currently rebuild that fast, but they
/// will once workstream 007 puts live detection on these screens, and the leak
/// grows with uptime rather than announcing itself.
struct ModulePicker<Value: Hashable, Label: View>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    @ViewBuilder var label: (Value) -> Label

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    label(value).tag(value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// One figure with its caption — the web's `.stat-grid` cell.
struct ModuleStat: View {
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint ?? .primary)
                // The value changes as the player interacts; without this a
                // digit appearing re-lays-out the row around it.
                .contentTransition(.numericText())
        }
        .frame(minWidth: 112, alignment: .leading)
    }
}

/// The theory copy under the stage. Prose, deliberately: this is the part that
/// teaches, and the web keeps it as paragraphs rather than bullet fragments.
struct ModuleProse: View {
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
    }
}

/// Shown on a module when a tap would produce no sound.
///
/// Exists because the first two modules shipped silently broken: every tap
/// called into a playback path that was never initialised, and there was
/// nothing on screen — or in a log — to say so. A module that cannot make a
/// sound should say which of the two reasons applies rather than leaving the
/// player wondering whether they mis-tapped.
struct ModuleAudioNotice: View {
    let isReady: Bool
    let error: String?

    var body: some View {
        if let error {
            notice(
                "The bundled note library could not be loaded, so notes cannot play. \(error)",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        } else if !isReady {
            notice(
                "Notes will not sound until an audio device is connected — choose one in Settings.",
                systemImage: "speaker.slash.fill",
                tint: .secondary
            )
        }
    }

    private func notice(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: false, vertical: true)
    }
}
