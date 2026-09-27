import Foundation
import Observation

enum Phase1CaptureMode: String, CaseIterable, Identifiable, Sendable {
    // The sink is the selected capture primitive. Physical-device measurement
    // (iPhone 14 Pro Max, iOS 27.0) showed the tap delivering its requested
    // 1024-frame chunks as 4800-frame (~100 ms) callbacks at ~10/s, while the
    // sink delivered 1120-frame (~23 ms) callbacks at ~44/s — so the tap was
    // deleted (Workstream 009 Phase 1). Sink first: it is the default and the
    // only source that reflects what the player is actually doing.
    case microphoneSink
    case synthetic

    var id: String { rawValue }

    /// Live capture opens the microphone; the synthetic tone is a diagnostic
    /// that feeds the detector a known signal without touching the mic.
    var isLiveMicrophone: Bool { self != .synthetic }

    var label: String {
        switch self {
        case .microphoneSink: "Live microphone (sink)"
        case .synthetic: "Diagnostic tone (synthetic A4)"
        }
    }

    /// Phrased for the status row so the running source is never ambiguous.
    var statusLabel: String {
        switch self {
        case .microphoneSink: "Listening — live microphone (sink)"
        case .synthetic: "Diagnostic — synthetic 440 Hz, not the microphone"
        }
    }
}

enum Phase1HarnessState: Equatable, Sendable {
    case idle
    case starting
    case running(Phase1CaptureMode)
    case permissionDenied
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .starting: "Starting…"
        case .running(let mode): mode.statusLabel
        case .permissionDenied: "Microphone permission denied"
        case .failed(let message): "Failed: \(message)"
        }
    }
}

@MainActor
protocol Phase1ManualCaptureSource: AnyObject {
    func start(mode: Phase1CaptureMode, pipeline: Phase1AnalysisPipeline) async throws
    func stop()
    /// Fixed session latencies, available once capture has started. Defaults to
    /// `nil` so non-hardware sources (the fakes, the synthetic feeder) need not
    /// know about `AVAudioSession`.
    func sessionMetrics() -> Phase1SessionMetrics?
}

extension Phase1ManualCaptureSource {
    func sessionMetrics() -> Phase1SessionMetrics? { nil }
}

@MainActor
@Observable
final class Phase1HarnessModel {
    private let makeManualSource: () -> Phase1ManualCaptureSource
    private var manualSource: Phase1ManualCaptureSource?
    private var syntheticFeeder: Phase1SyntheticFeeder?
    private var pipeline: Phase1AnalysisPipeline?
    private var startTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var generation: Int = 0
    /// Nonisolated, low-rate logger. It must outlive a blocked MainActor, so it
    /// keeps its own detached sampling task rather than reading telemetry in a
    /// view body.
    private let diagnostics = Phase1DiagnosticLogger()

    // Default to a live microphone: tapping Start must exercise the real input,
    // not the deterministic diagnostic tone. Synthetic stays selectable above.
    var selectedMode: Phase1CaptureMode = .microphoneSink
    private(set) var state: Phase1HarnessState = .idle
    private(set) var telemetry = Phase1AnalysisTelemetry()
    /// Realtime capture-callback count, sampled by `pollTask` while a live
    /// microphone run is active. This is deliberately separate from
    /// `telemetry.updateCount`: the latter only advances when the analysis
    /// worker publishes, so it cannot tell a silent worker apart from a
    /// capture callback that never fired.
    private(set) var rawCallbackCount: Int = 0

    init(
        makeManualSource: @escaping () -> Phase1ManualCaptureSource = { Phase1MicrophoneHarness() }
    ) {
        self.makeManualSource = makeManualSource
    }

    func start() {
        guard !state.isRunning, state != .starting else { return }
        state = .starting
        generation &+= 1
        telemetry = Phase1AnalysisTelemetry()
        rawCallbackCount = 0
        // Every explicit start gets a fresh pipeline/ring/worker.
        let pipeline = Phase1AnalysisPipeline()
        let gen = generation
        pipeline.onUpdate = { [weak self] update in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.telemetry = update
            }
        }
        self.pipeline = pipeline

        switch selectedMode {
        case .synthetic:
            let feeder = Phase1SyntheticFeeder(pipeline: pipeline)
            syntheticFeeder = feeder
            feeder.start()
            state = .running(.synthetic)

        case .microphoneSink:
            let source = makeManualSource()
            manualSource = source
            let mode = selectedMode
            let gen = generation
            beginPolling(pipeline: pipeline)
            diagnostics.start(pipeline: pipeline)
            let task = Task { @MainActor in
                do {
                    try await source.start(mode: mode, pipeline: pipeline)
                    guard gen == generation else {
                        source.stop()
                        return
                    }
                    if let metrics = source.sessionMetrics() {
                        diagnostics.logSessionStart(metrics)
                    }
                    state = .running(mode)
                } catch Phase1MicrophoneHarnessError.permissionDenied {
                    source.stop()
                    guard gen == generation else { return }
                    endPolling()
                    diagnostics.stop()
                    state = .permissionDenied
                } catch {
                    source.stop()
                    guard gen == generation else { return }
                    endPolling()
                    diagnostics.stop()
                    state = .failed(error.localizedDescription)
                }
            }
            startTask = task
        }
    }

    func stop() {
        generation &+= 1
        startTask?.cancel()
        startTask = nil
        endPolling()
        diagnostics.stop()
        syntheticFeeder?.stop()
        syntheticFeeder = nil
        manualSource?.stop()
        manualSource = nil
        pipeline?.stop()
        pipeline = nil
        state = .idle
    }

    /// Samples the pipeline's realtime callback counter while a live
    /// microphone run is active. Kept off the audio thread and out of the
    /// worker's publish path; ~4 Hz is enough to tell "callback firing" from
    /// "callback silent" without rebuilding the telemetry leaf any faster.
    private func beginPolling(pipeline: Phase1AnalysisPipeline) {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.pipeline === pipeline else { return }
                self.rawCallbackCount = pipeline.rawCallbackCountSnapshot()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func endPolling() {
        pollTask?.cancel()
        pollTask = nil
        rawCallbackCount = 0
    }
}
