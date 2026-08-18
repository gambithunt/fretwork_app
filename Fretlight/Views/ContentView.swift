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
            FretboardView(note: state.display.note).frame(minHeight: 260, maxHeight: .infinity)
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

    private var header: some View {
        // A plain sequential HStack, not a ZStack overlaying a centered
        // signalPath on top of the title. Centering via ZStack doesn't
        // reserve space for the title, so depending on width the two could
        // genuinely render on top of each other — that's what the garbled
        // "Fretwork"/"GP-200 Audio" overlap was. Laid out left-to-right,
        // overlap is structurally impossible: each element gets its own
        // space in sequence.
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                // Invisible label matching signalPath's controls, so the
                // title block sits at the exact same baseline as them
                // instead of just "somewhere in the middle" of a taller row.
                Text("FRETWORK").font(.caption2.weight(.medium)).foregroundStyle(.clear)
                HStack(spacing: 10) {
                    Text("Fretwork").font(.title2.weight(.bold))
                    Label(state.errorMessage == nil ? "Listening" : "Reconnecting", systemImage: "circle.fill")
                        .font(.callout).foregroundStyle(state.errorMessage == nil ? .green : .orange)
                }
                .frame(height: 44)
            }
            signalPath
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private var signalPath: some View {
        HStack(alignment: .top, spacing: 14) {
            routePicker("INPUT", devices: state.inputDevices, selection: state.selectedInputDeviceID, action: state.selectInputDevice)
            VStack(spacing: 5) {
                Text("ROUTE").font(.caption2.weight(.medium)).foregroundStyle(.clear)
                Image(systemName: "arrow.right").foregroundStyle(.secondary).frame(height: 44)
            }
            routePicker("OUTPUT", devices: state.outputDevices, selection: state.selectedOutputDeviceID, action: state.selectOutputDevice)
            rescanButton
            monitorControl
            sensitivityControl
        }
    }

    private var rescanButton: some View {
        VStack(spacing: 5) {
            // Invisible label matching the other controls' caption row,
            // so this button's icon sits at the same baseline as theirs.
            Text("RESCAN").font(.caption2.weight(.medium)).foregroundStyle(.clear)
            Button { state.refreshDevices() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .help("Rescan for input/output devices connected since launch")
            .frame(height: 44)
        }
    }

    private var monitorControl: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MONITOR").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { state.monitorMuted.toggle() } label: {
                    Image(systemName: state.monitorMuted ? "speaker.slash" : "speaker.wave.2")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .help(state.monitorMuted ? "Unmute direct monitoring" : "Mute direct monitoring")
                Slider(value: $state.monitorVolume, in: 0...1)
                    .frame(width: 118)
                    .disabled(state.monitorMuted)
            }
            .frame(height: 44)
        }
    }

    private var sensitivityControl: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SENSITIVITY").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $state.sensitivity, in: 0...1)
                    .frame(width: 118)
                    .help("Strict: fewer false triggers on noisy signal. Lenient: catches weaker or quieter notes.")
            }
            .frame(height: 44)
        }
    }

    private func routePicker(_ label: String, devices: [AudioDevice], selection: AudioDeviceID?, action: @escaping (AudioDeviceID?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            DevicePickerView(title: label, devices: devices, selection: selection, onSelect: action)
        }
    }

    private var telemetry: some View {
        HStack(spacing: 24) {
            Label("\(state.display.bufferSize) frames", systemImage: "waveform")
            Divider().frame(height: 20)
            Label(String(format: "%.1f ms", state.display.latencyMilliseconds), systemImage: "timer")
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
