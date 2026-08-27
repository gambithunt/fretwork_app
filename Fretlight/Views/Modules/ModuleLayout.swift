import SwiftUI

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
    @ViewBuilder var controls: Controls
    @ViewBuilder var stage: Stage
    @ViewBuilder var readout: Readout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controls
                stage
                readout
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.035, green: 0.045, blue: 0.047))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(module.title)
                .font(.largeTitle.weight(.semibold))
            Text(module.blurb)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .font(.title3.weight(.medium))
                .foregroundStyle(tint ?? .primary)
                // The value changes as the player interacts; without this a
                // digit appearing re-lays-out the row around it.
                .contentTransition(.numericText())
        }
        .frame(minWidth: 90, alignment: .leading)
    }
}

/// The theory copy under the stage. Prose, deliberately: this is the part that
/// teaches, and the web keeps it as paragraphs rather than bullet fragments.
struct ModuleProse: View {
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
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
