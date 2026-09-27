import SwiftUI

struct Phase1HarnessView: View {
    @State private var model = Phase1HarnessModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Phase 1 capture harness") {
                    Text("Launch is inert. Capture starts only after tapping Start. Live microphone asks for permission and analyses what the device hears; the diagnostic tone feeds the detector a known signal without touching microphone permission or AVAudioSession.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Input source") {
                    Picker("Source", selection: $model.selectedMode) {
                        ForEach(Phase1CaptureMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .disabled(model.state.isRunning || model.state == .starting)

                    // Always-visible statement of what Start will do, so the
                    // selected source cannot be mistaken for live input.
                    Label {
                        Text(sourceSummary)
                    } icon: {
                        Image(systemName: model.selectedMode.isLiveMicrophone ? "mic.fill" : "waveform.path.ecg")
                    }
                    .font(.footnote)
                    .foregroundStyle(model.selectedMode.isLiveMicrophone ? Color.primary : Color.orange)

                    HStack {
                        Button("Start") { model.start() }
                            .disabled(model.state.isRunning || model.state == .starting)
                        Button("Stop") { model.stop() }
                            .disabled(!model.state.isRunning && model.state != .starting)
                    }
                }

                Section("State") {
                    LabeledContent("Status", value: model.state.label)
                    if showsRawCallbackDiagnostics {
                        Phase1RawCallbackRow(model: model)
                        Text("Raw counts microphone capture callbacks; Updates counts analysis publications. Raw climbing while Updates stays 0 means audio is arriving but the worker is producing no results.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if model.state == .permissionDenied {
                        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }

                Phase1TelemetrySection(model: model)

                Section("Graph rule") {
                    Label("No microphone-to-speaker connection is created. The sink connects input to AVAudioSinkNode for analysis only.", systemImage: "speaker.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Fretwork")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                model.stop()
            }
        }
    }

    /// What the selected source means for the Start button, phrased so live
    /// microphone and diagnostic tone can never be confused.
    private var sourceSummary: String {
        switch model.state {
        case .starting:
            return "Starting \(model.selectedMode.label)…"
        case .running(let mode):
            return mode.statusLabel
        case .idle, .permissionDenied, .failed:
            return model.selectedMode.isLiveMicrophone
                ? "Start opens the live microphone and analyses what it hears."
                : "Diagnostic only: a synthetic 440 Hz tone is analysed, not the microphone."
        }
    }

    /// Raw callbacks are microphone capture callbacks; the synthetic feeder also
    /// writes through the same pipeline, so showing the counter for the
    /// diagnostic tone would mislabel its writes. Only show it for live input.
    private var showsRawCallbackDiagnostics: Bool {
        model.selectedMode.isLiveMicrophone && (model.state == .starting || model.state.isRunning)
    }
}

private struct Phase1RawCallbackRow: View {
    // Read the fast-changing atomic counter in its own leaf so the picker and
    // controls above are not rebuilt on every poll.
    let model: Phase1HarnessModel

    var body: some View {
        LabeledContent("Microphone callbacks (raw)", value: "\(model.rawCallbackCount)")
    }
}

private struct Phase1TelemetrySection: View {
    // Read the fast-changing telemetry in this leaf so the source picker and
    // controls above are not rebuilt on every audio update (C-10).
    let model: Phase1HarnessModel

    var body: some View {
        Section("Telemetry") {
            let telemetry = model.telemetry
            LabeledContent("Latest note", value: telemetry.latestNoteLabel)
            LabeledContent("Frequency", value: telemetry.latestPitch.frequency.map { String(format: "%.1f Hz", $0) } ?? "—")
            LabeledContent("Level", value: String(format: "%.4f", telemetry.latestPitch.level))
            LabeledContent("Updates", value: "\(telemetry.updateCount)")
            LabeledContent("Sample rate", value: telemetry.sampleRate > 0 ? String(format: "%.0f Hz", telemetry.sampleRate) : "—")
            LabeledContent("Last callback frames", value: telemetry.lastCallbackFrameCount > 0 ? "\(telemetry.lastCallbackFrameCount)" : "—")
            if !telemetry.callbackFrameHistogram.isEmpty {
                Text(histogramText(for: telemetry))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func histogramText(for telemetry: Phase1AnalysisTelemetry) -> String {
        telemetry.callbackFrameHistogram
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "  ")
    }
}

#Preview {
    Phase1HarnessView()
}
