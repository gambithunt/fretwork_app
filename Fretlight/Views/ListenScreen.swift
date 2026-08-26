import SwiftUI
import CoreAudio

/// The app's original and default screen: device selection, live detection
/// readouts, history and the fretboard.
///
/// Extracted verbatim from `ContentView` when the app gained more than one
/// screen (workstream 005). Nothing about it changed in the move — including
/// the leaf-view split below, which is load-bearing rather than stylistic.
struct ListenScreen: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            header
            if let error = state.errorMessage {
                audioErrorBanner(error)
            } else if state.isReconnecting {
                reconnectingBanner
            } else if let hint = state.unclearSignalMessage {
                signalHintBanner(hint)
            }
            // The three live readouts and the board below each read the
            // audio-rate properties (`display`, `chordDisplay`, the
            // `displayed*` derivations) from inside their *own* body rather
            // than from this one. `@Observable` tracks reads per view body,
            // so reading them here would make every one of those ~30
            // updates a second invalidate this whole `VStack` — header,
            // device pickers and detection-mode control included — none of
            // which has anything to do with the incoming audio. Keeping the
            // reads in leaf views is what confines each update to the view
            // that actually shows the changed value.
            TunerSection(state: state)
            LevelSection(state: state)
            TelemetrySection(state: state)
            // The strip sits under the readouts and the flip control sits
            // directly above the board it flips, so each control is adjacent
            // to what it acts on. One strip per mode, same component,
            // different entry type.
            switch state.detectionMode {
            case .chords:
                HistoryStrip(
                    history: state.chordHistory,
                    pinnedID: state.pinnedChordHistoryID,
                    label: { $0.match.name },
                    tint: { NotePalette.color(for: $0.match.root) },
                    noun: "chord",
                    onSelect: { state.pinnedChordHistoryID = $0 },
                    onClear: { state.clearChordHistory() }
                )
            case .notes:
                HistoryStrip(
                    history: state.noteHistory,
                    pinnedID: state.pinnedNoteHistoryID,
                    label: { "\($0.note.name)\($0.note.octave)" },
                    tint: { NotePalette.color(for: $0.note.name) },
                    noun: "note",
                    onSelect: { state.pinnedNoteHistoryID = $0 },
                    onClear: { state.clearNoteHistory() }
                )
            }
            fretboardControls
            BoardSection(state: state)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.045, blue: 0.047))
        .preferredColorScheme(.dark)
    }

    // Every block in the top bar is laid out the same way: a fixed-height
    // caption row above a fixed-height control row. Because the two heights
    // are shared constants, all captions land on one line and all controls
    // land on another, no matter what each control's natural size is — the
    // pickers used to float above the buttons and sliders because only some
    // of them pinned a height.
    private enum HeaderMetrics {
        static let captionRow: CGFloat = 13
        static let controlRow: CGFloat = 32
        static let gap: CGFloat = 6
        static var blockHeight: CGFloat { captionRow + gap + controlRow }
    }

    private var header: some View {
        // A plain sequential HStack, not a ZStack overlaying a centered
        // signalPath on top of the brand. Centering via ZStack doesn't
        // reserve space for the brand, so depending on width the two could
        // genuinely render on top of each other — that's what the garbled
        // "Fretwork"/"GP-200 Audio" overlap was. Laid out left-to-right,
        // overlap is structurally impossible: each element gets its own
        // space in sequence.
        HStack(alignment: .center, spacing: 20) {
            brand
            Divider().frame(height: HeaderMetrics.controlRow)
            signalPath
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            // The app icon's lettering is the wordmark, so it stands in for
            // the title outright. Sized to the full two-row height of the
            // controls beside it so the emblem's script stays legible.
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: HeaderMetrics.blockHeight)
                .accessibilityLabel("Fretwork")
            Label(state.errorMessage == nil && !state.isReconnecting ? "Listening" : "Reconnecting", systemImage: "circle.fill")
                .font(.callout).foregroundStyle(state.errorMessage == nil && !state.isReconnecting ? .green : .orange)
        }
    }

    private var signalPath: some View {
        HStack(alignment: .top, spacing: 14) {
            labeled("INPUT") {
                DevicePickerView(title: "INPUT", devices: state.inputDevices, selection: state.selectedInputDeviceID, onSelect: state.selectInputDevice)
            }
            labeled("") {
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            }
            labeled("OUTPUT") {
                DevicePickerView(title: "OUTPUT", devices: state.outputDevices, selection: state.selectedOutputDeviceID, onSelect: state.selectOutputDevice)
            }
            labeled("") { rescanButton }
            labeled("MONITOR") { monitorControl }
            labeled("SENSITIVITY") { sensitivityControl }
            labeled("DETECT") { detectionModeControl }
        }
    }

    // Caption above control, both on their shared fixed rows. An empty label
    // still reserves its row, which is how the unlabelled arrow and rescan
    // button stay in line with the labelled controls.
    private func labeled<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HeaderMetrics.gap) {
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: HeaderMetrics.captionRow, alignment: .bottom)
            content()
                .frame(height: HeaderMetrics.controlRow)
        }
    }

    private var rescanButton: some View {
        Button { state.refreshDevices() } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .help("Rescan for input/output devices connected since launch")
    }

    private var monitorControl: some View {
        HStack(spacing: 8) {
            Button { state.monitorMuted.toggle() } label: {
                Image(systemName: state.monitorMuted ? "speaker.slash" : "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .help(state.monitorMuted ? "Unmute direct monitoring" : "Mute direct monitoring")
            RulerSlider(value: $state.monitorVolume, isEnabled: !state.monitorMuted)
                .frame(width: 118)
        }
    }

    private var detectionModeControl: some View {
        Picker("Detection mode", selection: $state.detectionMode) {
            ForEach(DetectionMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 130)
        .help("Notes: tune one string at a time. Chords: name what's strummed.")
    }

    private var sensitivityControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(.secondary)
            RulerSlider(value: $state.sensitivity)
                .frame(width: 118)
                .help("Strict: fewer false triggers on noisy signal. Lenient: catches weaker or quieter notes.")
        }
    }

    /// Laid out against the widest value it can show, with the live value
    /// overlaid on top. A digit appearing or disappearing used to re-lay-out
    /// the whole row, shoving everything to its right sideways; reserving the
    /// space means the row's geometry no longer depends on the number in it.
    /// Precision follows the scale: tenths matter at 2ms on the direct path,
    /// and are pure jitter at 100ms on the buffered one.
    // A sequential HStack with a trailing Spacer, not a leading-aligned
    // frame — same reasoning as `header`: this reserves the button its own
    // space on the left rather than relying on alignment to keep it there.
    // A button naming the current top string, not a switch: it reads as one
    // action to take rather than a state to parse, and at `.callout`/
    // `.small` it sits at the same visual weight as `telemetry` right below
    // it instead of towering over that row the way a full-size native
    // switch did.
    private var fretboardControls: some View {
        HStack {
            Button {
                state.isFretboardFlipped.toggle()
            } label: {
                Label(state.isFretboardFlipped ? "Low E on top" : "High E on top", systemImage: "arrow.up.arrow.down")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.secondary)
            .help("Flip the fretboard: swap which string draws at the top.")
            Spacer(minLength: 0)
        }
    }

    /// Shown for the automatic-recovery window itself, before it's known to
    /// succeed or fail — `audioErrorBanner` only appears once that's given
    /// up. Without this, that whole window (a device drops out, a few
    /// retries happen a beat apart) shows nothing but a silent meter, which
    /// reads as the app having frozen rather than as it working on it.
    private var reconnectingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Reconnecting to audio device…").font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    /// A softer, non-error nudge: the connection is fine and audio is
    /// coming in, but nothing is resolving a confident note/chord from it —
    /// distinct from `audioErrorBanner`, which is about the device itself.
    private func signalHintBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.badge.exclamationmark").foregroundStyle(.secondary)
            Text(message).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func audioErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Audio connection lost").font(.callout.weight(.semibold))
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Button("Retry") { state.retryAudio() }
            Button("Refresh devices") { state.refreshDevices(); state.retryAudio() }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Live sections
//
// Each of these exists purely to own one read of the audio-rate state. They
// take the `AppState` itself rather than the already-read values, because a
// value read in `ListenScreen.body` and passed down would put the
// `@Observable` dependency back on `ListenScreen` — the very thing this split
// exists to avoid. See the note in `ListenScreen.body`.

private struct TunerSection: View {
    let state: AppState

    var body: some View {
        TunerPanel(mode: state.detectionMode, display: state.display, chord: state.chordDisplay)
    }
}

private struct LevelSection: View {
    let state: AppState

    var body: some View {
        InputLevelPanel(level: state.display.level)
    }
}

private struct BoardSection: View {
    let state: AppState

    var body: some View {
        // Grows to take up whatever's left in the window rather than a
        // fixed height, but never shrinks below a size that keeps the
        // fret labels and note markers legible — FretworkApp's minHeight
        // is sized so the rest of the VStack plus this floor always fit.
        // Stays mounted across both modes — Chords mode draws the
        // detected chord's shape here instead of hiding the board, so
        // switching modes never collapses the layout.
        FretboardView(
            mode: state.detectionMode,
            note: state.displayedNote,
            positions: state.displayedPositions,
            chord: state.displayedChord,
            flipped: state.isFretboardFlipped
        )
        .frame(minHeight: 260, maxHeight: .infinity)
    }
}

private struct TelemetrySection: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 24) {
            Label("\(state.display.bufferSize) frames", systemImage: "waveform")
                .help("Hardware IO buffer actually in force on the input device.")
            Divider().frame(height: 20)
            latencyReadout
            Divider().frame(height: 20)
            Label(state.display.isDirectMonitoring ? "Direct" : "Buffered",
                  systemImage: state.display.isDirectMonitoring ? "bolt.fill" : "arrow.triangle.swap")
                .help(state.display.isDirectMonitoring
                      ? "One device, one clock: monitoring stays inside a single render graph."
                      : "Input and output are separate devices, so audio is buffered between them, which costs noticeable delay.")
            if let candidate = state.directMonitoringCandidate {
                Button("Monitor through \(candidate.name)") { state.useInputDeviceForOutput() }
                    .buttonStyle(.link)
                    .help("Play back through the same device the guitar comes in on. Capture and playback then share one clock, which removes most of the monitoring delay.")
            }
        }
        .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }

    /// Laid out against the widest value it can show, with the live value
    /// overlaid on top. A digit appearing or disappearing used to re-lay-out
    /// the whole row, shoving everything to its right sideways; reserving the
    /// space means the row's geometry no longer depends on the number in it.
    /// Precision follows the scale: tenths matter at 2ms on the direct path,
    /// and are pure jitter at 100ms on the buffered one.
    private var latencyReadout: some View {
        let milliseconds = state.display.latencyMilliseconds
        let text = milliseconds < 10
            ? String(format: "%.1f ms", milliseconds)
            : String(format: "%.0f ms", milliseconds)
        return Label("999 ms", systemImage: "timer")
            .hidden()
            .overlay(alignment: .leading) { Label(text, systemImage: "timer") }
    }
}

/// The window's root view.
///
/// A container rather than the screen itself, so the app can grow more screens
/// without `FretlightApp` reaching past it. Workstream 005 Phase 2 replaces the
/// body with a navigation shell; until then it is the listening screen and
/// nothing else, which keeps this phase a pure move.
struct ContentView: View {
    @Bindable var state: AppState

    var body: some View {
        AppShell(state: state)
            // The engine is started here, once, for the window's lifetime —
            // not from `ListenScreen`, where this used to live. A screen's
            // `.task` re-runs every time that screen reappears, and
            // `AppState.start()` is a full stop-and-rebuild of the graph, so
            // leaving it there would have made every visit to the listening
            // screen restart audio: a re-prompt for the microphone, a dropped
            // direct-monitoring path, and a new trigger for the very restart
            // path `AudioEngine` debounces and rate-limits because an uncapped
            // restart loop was once a real bug.
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                state.start()
            }
    }
}
