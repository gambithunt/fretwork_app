import SwiftUI
import CoreAudio

struct ContentView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            header
            if let error = state.errorMessage { audioErrorBanner(error) }
            TunerPanel(display: state.display)
            InputLevelPanel(level: state.display.level)
            telemetry
            // Grows to take up whatever's left in the window rather than a
            // fixed height, but never shrinks below a size that keeps the
            // fret labels and note markers legible — FretworkApp's minHeight
            // is sized so the rest of this VStack plus this floor always fit.
            FretboardView(note: state.display.note, positions: state.fretPositions).frame(minHeight: 260, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.045, blue: 0.047))
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            state.start()
        }
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
            Label(state.errorMessage == nil ? "Listening" : "Reconnecting", systemImage: "circle.fill")
                .font(.callout).foregroundStyle(state.errorMessage == nil ? .green : .orange)
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

    private var sensitivityControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(.secondary)
            RulerSlider(value: $state.sensitivity)
                .frame(width: 118)
                .help("Strict: fewer false triggers on noisy signal. Lenient: catches weaker or quieter notes.")
        }
    }

    private var telemetry: some View {
        HStack(spacing: 24) {
            Label("\(state.display.bufferSize) frames", systemImage: "waveform")
                .help("Hardware IO buffer actually in force on the input device.")
            Divider().frame(height: 20)
            Label(String(format: "%.1f ms", state.display.latencyMilliseconds), systemImage: "timer")
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
