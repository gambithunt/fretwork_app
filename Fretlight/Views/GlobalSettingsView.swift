import SwiftUI

/// The settings that belong to the instrument and the room rather than to any
/// one screen: which devices are in use, how loud monitoring is, how eager
/// detection is, what the guitar is tuned to, and which way up the board is
/// drawn.
///
/// These used to live in the listening screen's header, which was right while
/// that was the only screen. Once the app has ten module screens that all draw
/// a board and sound notes through the same devices, a setting reachable from
/// only one of them is a setting the player has to navigate away to change.
///
/// **No audio-rate reads here.** This is presented from the shell's toolbar, so
/// a `display`/`chordDisplay` read in this body would put a ~30 Hz dependency
/// on the toolbar of every screen in the app. The values it does read —
/// devices, volume, sensitivity, tuning — change only when a person changes
/// them.
struct GlobalSettingsView: View {
    @Bindable var state: AppState

    /// Every row's label sits in a column this wide, so every control begins
    /// at the same x no matter how long its label is. A plain `VStack` of
    /// `LabeledContent` (or a `Grid`, which centres a menu `Picker` in its
    /// cell) let the controls step in and out as "Input" gave way to
    /// "Sensitivity".
    private let labelColumnWidth: CGFloat = 92
    /// The three menu pickers share one width so their left *and* right edges
    /// line up, rather than each hugging its current value.
    private let pickerWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Devices") {
                row("Input") {
                    DevicePickerView(
                        title: "INPUT",
                        devices: state.inputDevices,
                        selection: state.selectedInputDeviceID,
                        onSelect: state.selectInputDevice
                    )
                    .frame(width: pickerWidth)
                }
                row("Output") {
                    DevicePickerView(
                        title: "OUTPUT",
                        devices: state.outputDevices,
                        selection: state.selectedOutputDeviceID,
                        onSelect: state.selectOutputDevice
                    )
                    .frame(width: pickerWidth)
                }
                row(nil) {
                    Button {
                        state.refreshDevices()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .help("Rescan for input/output devices connected since launch")
                }
            }

            section("Monitoring") {
                row("Monitor") {
                    Button {
                        state.monitorMuted.toggle()
                    } label: {
                        Image(systemName: state.monitorMuted ? "speaker.slash" : "speaker.wave.2")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .help(state.monitorMuted ? "Unmute direct monitoring" : "Mute direct monitoring")
                    RulerSlider(value: $state.monitorVolume, isEnabled: !state.monitorMuted)
                        .frame(width: 140)
                }
                row("Sensitivity") {
                    RulerSlider(value: $state.sensitivity)
                        .frame(width: 140)
                        .help("Strict: fewer false triggers on noisy signal. Lenient: catches weaker or quieter notes.")
                }
            }

            section("Instrument") {
                row("Tuning") {
                    // Menu style, never `.segmented`: `CLAUDE.md` records a
                    // measured registrar leak from a segmented picker rebuilt
                    // at audio rate, and this control sits in the toolbar of
                    // every screen.
                    Picker("Tuning", selection: $state.tuning) {
                        ForEach(Tunings.all, id: \.self) { tuning in
                            Text("\(tuning.name) · \(tuning.display)").tag(tuning)
                        }
                    }
                    .labelsHidden()
                    .frame(width: pickerWidth)
                }
                row("Board") {
                    Button {
                        state.isFretboardFlipped.toggle()
                    } label: {
                        Label(
                            state.isFretboardFlipped ? "Low E on top" : "High E on top",
                            systemImage: "arrow.up.arrow.down"
                        )
                    }
                    .help("Which string is drawn along the top of every board")
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// A label/control row. The label occupies a fixed-width leading column;
    /// the control follows immediately after it, so the control's left edge is
    /// identical on every row. `nil` keeps the column (the Rescan button lines
    /// up under the device pickers) without drawing a label.
    private func row<Control: View>(
        _ label: String?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label ?? "")
                .frame(width: labelColumnWidth, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }
}
