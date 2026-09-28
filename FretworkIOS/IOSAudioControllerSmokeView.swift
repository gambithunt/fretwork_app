import Darwin
import SwiftUI

/// A deliberately tiny Phase 3 smoke entry: enough to start/stop capture, play
/// a sample, and read the iOS status off the console before the Phase 4 shell
/// exists. It is **not** the production UI.
///
/// Every status change writes one line to stderr so a physical-device run can be
/// read with `devicectl device process launch … --console` without root. The
/// line carries the status plus the session's sample rate, input channel count
/// and the active category/mode, which is what design checks D-1/D-7 ask for.
struct IOSAudioControllerSmokeView: View {
    @State private var appState = AppState()

    var body: some View {
        let controller = appState.iosAudio
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Status", value: statusLabel(controller?.status))
                    LabeledContent("Sample rate", value: controller.map { String(format: "%.0f Hz", $0.sessionSampleRate) } ?? "—")
                    LabeledContent("Input channels", value: controller.map { "\($0.sessionInputChannelCount)" } ?? "—")
                    LabeledContent("Category / mode", value: controller?.sessionConfigurationDescription ?? "—")
                    LabeledContent("Sample library", value: libraryLabel(controller))
                }

                Section("Capture") {
                    HStack {
                        Button("Start") { appState.start() }
                        Button("Stop") { appState.iosAudio?.stop() }
                    }
                }

                Section("Sample playback") {
                    Button("Load samples") { controller?.prepareSamplePlayback(completion: nil) }
                    HStack {
                        Button("Play low E") { play(string: 0, fret: 0) }
                        Button("Play A2") { play(string: 1, fret: 0) }
                    }
                    .disabled(!(controller?.isSamplePlaybackReady ?? false))
                    Text("The first tap after loading builds the output-only graph; tap again to hear it.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Console") {
                    Text("Each status change writes one line to stderr for `devicectl … --console`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Fretwork smoke")
            .task { logStatus(controller?.status) }
            .onChange(of: appState.iosAudio?.status) { _, newStatus in
                logStatus(newStatus)
            }
        }
    }

    private func play(string: Int, fret: Int) {
        appState.iosAudio?.playSample(string: string, fret: fret, tuning: appState.tuning)
    }

    private func statusLabel(_ status: IOSAudioStatus?) -> String {
        switch status {
        case .idle: "idle"
        case .starting: "starting"
        case .listening: "listening"
        case .interrupted: "interrupted"
        case .permissionDenied: "permissionDenied"
        case .failed(let message): "failed: \(message)"
        case nil: "no controller"
        }
    }

    private func libraryLabel(_ controller: IOSAudioController?) -> String {
        if controller?.isSamplePlaybackReady == true { return "ready" }
        if controller?.isSampleLibraryLoaded == true { return "loaded" }
        return "not loaded"
    }

    private func logStatus(_ status: IOSAudioStatus?) {
        guard let controller = appState.iosAudio else { return }
        let line = "ios-audio status=\(statusLabel(status))"
            + " sampleRate=\(Int(controller.sessionSampleRate))"
            + " channelCount=\(controller.sessionInputChannelCount)"
            + " category=\(controller.sessionConfigurationDescription)"
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

#Preview {
    IOSAudioControllerSmokeView()
}
