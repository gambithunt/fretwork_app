import Foundation
import os

/// One low-rate diagnostic sample of the Phase 1 capture path.
///
/// Two fields, two questions: is the realtime capture callback still firing
/// (`rawCallbacks`), and is the analysis worker still publishing (`updates`)?
/// Raw climbing while updates stays flat means audio is arriving but the
/// worker is not producing results; both flat means the callback stopped.
struct Phase1DiagnosticSample: Equatable, Sendable {
    var rawCallbacks: Int
    var updates: Int
}

/// Nonisolated, low-rate logger for the Phase 1 capture harness.
///
/// Deliberately **not** MainActor-bound. The failure it exists to diagnose is a
/// UI that stops responding, and a MainActor-bound logger would fall silent at
/// exactly that moment. It reads only:
///   * `Phase1AnalysisPipeline.rawCallbackCountSnapshot()` — lock-free atomic;
///   * `Phase1AnalysisPipeline.snapshot()` — the pipeline lock, which the
///     analysis worker holds only for a telemetry copy, never across a
///     blocking call.
///
/// It never runs on the audio callback thread, never adds a lock to it, and
/// never allocates there. Each sample runs on a detached, `.utility` task so it
/// keeps producing output even when the main thread is blocked. Each sample is
/// written both to `os.Logger` and, as a plain line, to stderr so
/// `devicectl device process launch --console` can capture it without root.
/// The line carries counters only — no device identifiers or other details.
final class Phase1DiagnosticLogger: @unchecked Sendable {
    static let subsystem = "org.fretwork.app"
    static let category = "phase1-capture"

    private let log = Logger(subsystem: Phase1DiagnosticLogger.subsystem,
                             category: Phase1DiagnosticLogger.category)
    private let interval: Duration
    private let stateLock = NSLock()
    private var pipeline: Phase1AnalysisPipeline?
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(2)) {
        self.interval = interval
    }

    /// Begins sampling `pipeline` until `stop()`. Safe to call from the
    /// MainActor; the sampling itself is detached from it.
    func start(pipeline: Phase1AnalysisPipeline) {
        stop()
        stateLock.lock()
        self.pipeline = pipeline
        stateLock.unlock()
        let interval = self.interval
        task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.logOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        stateLock.lock()
        pipeline = nil
        stateLock.unlock()
    }

    /// Reads one sample without logging. Split out so tests can assert the
    /// counters the logger reports without parsing `os_log` output.
    func sample() -> Phase1DiagnosticSample? {
        stateLock.lock()
        let pipeline = self.pipeline
        stateLock.unlock()
        guard let pipeline else { return nil }
        return Phase1DiagnosticSample(
            rawCallbacks: pipeline.rawCallbackCountSnapshot(),
            updates: pipeline.snapshot().updateCount
        )
    }

    private func logOnce() {
        guard let sample = sample() else { return }
        var line = "phase1 raw=\(sample.rawCallbacks) updates=\(sample.updates)"
        stateLock.lock()
        let pipeline = self.pipeline
        stateLock.unlock()
        if let t = pipeline?.snapshot() {
            // Enough to compare capture primitives from the console alone:
            // callback size and its spread, then what the detector made of it.
            let histogram = t.callbackFrameHistogram.sorted { $0.key < $1.key }
                .map { "\($0.key)x\($0.value)" }.joined(separator: ",")
            let p = t.latestPitch
            line += " sr=\(Int(t.sampleRate)) frames=\(t.lastCallbackFrameCount) hist=[\(histogram)]"
            line += " note=\(t.latestNoteLabel) hz=\(p.frequency.map { String(format: "%.1f", $0) } ?? "-")"
            line += String(format: " conf=%.2f level=%.4f latencyMs=%.1f", p.confidence, p.level, p.latencyMilliseconds)
        }
        log.notice("\(line, privacy: .public)")
        // stderr mirror for `devicectl ... --console`, which needs no root and
        // unlike `log collect` works against a device.
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
