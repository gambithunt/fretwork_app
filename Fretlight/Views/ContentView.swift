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
            FretboardView(note: state.display.note).frame(height: 335)
        }
        .padding(24)
        .background(Color(red: 0.035, green: 0.045, blue: 0.047))
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            state.start()
        }
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 10) {
                Text("Fretwork").font(.title2.weight(.bold))
                Label(state.errorMessage == nil ? "Listening" : "Reconnecting", systemImage: "circle.fill")
                    .font(.callout).foregroundStyle(state.errorMessage == nil ? .green : .orange)
            }
            HStack { Spacer(); signalPath; Spacer() }
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
            monitorControl
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
