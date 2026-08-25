#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

/// Owns the capture session and wires the recorder to it.
///
/// Separate from `SampleCaptureView` so the view stays constructible from a
/// test without an `AppState` or a live audio graph behind it.
struct SampleCaptureHost: View {
    let state: AppState

    @State private var model: SampleCaptureModel?
    @State private var meter = CaptureLevelMeter()
    @State private var arm = CaptureArmState()
    @State private var directory = SampleCaptureDirectory.url
    @State private var choosingDirectory = false

    var body: some View {
        Group {
            if let model {
                SampleCaptureView(
                    model: model,
                    meter: meter,
                    arm: arm,
                    onArm: startWaiting,
                    onDisarm: stopWaiting,
                    onChooseDirectory: { choosingDirectory = true }
                )
            } else {
                chooseFolderPrompt
            }
        }
        .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            SampleCaptureDirectory.url = url
            directory = url
            makeModel(at: url)
        }
        .onAppear {
            if let directory { makeModel(at: directory) }
            state.setSampleRecordingEnabled(true)
        }
        .onDisappear {
            stopWaiting()
            state.setSampleRecordingEnabled(false)
        }
    }

    private var chooseFolderPrompt: some View {
        VStack(spacing: 12) {
            Text("Choose a folder for the sample masters.")
                .font(.title3)
            Button("Choose folder…") { choosingDirectory = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.045, blue: 0.047))
        .preferredColorScheme(.dark)
    }

    private func makeModel(at url: URL) {
        let model = SampleCaptureModel(directory: url)
        self.model = model
        // Captured directly rather than through `self`: these callbacks fire on
        // the recorder's own queue, and a `View` struct is not `Sendable`.
        let meter = meter
        let arm = arm
        state.sampleRecorder.onLevel = { level in
            Task { @MainActor in meter.update(level) }
        }
        state.sampleRecorder.onTake = { take in
            Task { @MainActor in
                model.handle(take: take)
                // Every take is a deliberate act, so arming does not persist
                // past one — the same reason the recorder returns to idle.
                arm.isArmed = false
            }
        }
    }

    private func startWaiting() {
        arm.isArmed = true
        state.sampleRecorder.arm()
    }

    private func stopWaiting() {
        arm.isArmed = false
        state.sampleRecorder.disarm()
    }
}
#endif
