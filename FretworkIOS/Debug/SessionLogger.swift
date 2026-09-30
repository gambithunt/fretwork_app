#if DEBUG
import Foundation
import Observation

/// Pure formatting for the DEBUG `-FretworkSessionLog` stream. Kept separate
/// from the observer so the line shapes are unit-testable without standing up
/// an `AppState` or a controller.
enum SessionLogFormat {
    static func seconds(_ t: Double) -> String { String(format: "%.3f", t) }

    static func decibels(_ level: Float) -> Double {
        20 * log10(max(Double(level), 0.000_001))
    }

    static func noteLine(t: Double, note: MappedNote?, confidence: Float, level: Float) -> String {
        let name = note.map { "\($0.name)\($0.octave)" } ?? "none"
        let cents = note.map { String(format: "%.1f", $0.cents) } ?? "-"
        return "SESSION t=\(seconds(t)) note=\(name) cents=\(cents)"
            + " conf=\(String(format: "%.3f", confidence))"
            + " level=\(String(format: "%.1f", decibels(level)))"
    }

    static func chordLine(t: Double, chord: String?) -> String {
        "SESSION t=\(seconds(t)) chord=\(chord ?? "none")"
    }

    static func gateLine(t: Double, closed: Bool) -> String {
        "SESSION t=\(seconds(t)) gate=\(closed ? "closed" : "opened")"
    }

    static func statusLine(t: Double, status: IOSAudioStatus?) -> String {
        "SESSION t=\(seconds(t)) status=\(statusDescription(status))"
    }

    static func summaryLine(
        notes: Int,
        distinctPitchClasses: Int,
        onsetMedian: Double?,
        onsetP90: Double?,
        noiseFloor: Float
    ) -> String {
        let median = onsetMedian.map { String(format: "%.3f", $0) } ?? "-"
        let p90 = onsetP90.map { String(format: "%.3f", $0) } ?? "-"
        return "SESSION summary notes=\(notes) distinctPC=\(distinctPitchClasses)"
            + " onsetMedian=\(median) onsetP90=\(p90)"
            + " noiseFloor=\(String(format: "%.1f", decibels(noiseFloor)))"
    }

    static func statusDescription(_ status: IOSAudioStatus?) -> String {
        switch status {
        case .idle: "idle"
        case .starting: "starting"
        case .listening: "listening"
        case .interrupted: "interrupted"
        case .permissionDenied: "permissionDenied"
        case .failed(let message): "failed:\(message)"
        case nil: "none"
        }
    }
}

/// The DEBUG-only session observer. It reads the *gated* surface `AppState`
/// sees — `display` and `chordDisplay` only change when a gated note/chord
/// event lands — plus the controller's gate and status, and writes one stderr
/// line per change (a confirmed-note change, a chord change, a gate transition,
/// a status transition) plus a 30 s summary.
///
/// `withObservationTracking` is re-armed after every fire so no view is
/// involved and no audio-rate property is polled.
@MainActor
final class SessionLogger {
    private let appState: AppState
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var summaryTask: Task<Void, Never>?

    // Tracked to log only on change.
    private var lastNoteMIDI: Int?
    private var lastChordName: String?
    private var lastGate: Bool?
    private var lastStatus: IOSAudioStatus?

    // Summary accumulation.
    private var notesConfirmed = 0
    private var pitchClasses = Set<Int>()
    private var onsetLatencies: [Double] = []
    private var silentLevels: [Float] = []
    private var onsetSince: Double?
    private var lastLevel: Float = 0
    private var lastLevelAboveThreshold = false

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Baseline: one line each so the log reads standalone from t=0.
        if let status = appState.iosAudio?.status {
            lastStatus = status
            write(SessionLogFormat.statusLine(t: 0, status: status))
        }
        if let gate = appState.iosAudio?.isSuppressingForPlayback {
            lastGate = gate
            write(SessionLogFormat.gateLine(t: 0, closed: gate))
        }
        observe()
        summaryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.logSummary()
            }
        }
    }

    func stop() {
        summaryTask?.cancel()
        summaryTask = nil
    }

    private func observe() {
        withObservationTracking {
            _ = appState.display.note?.midiNote
            _ = appState.display.note?.cents
            _ = appState.display.confidence
            _ = appState.display.level
            _ = appState.chordDisplay.chord?.name
            _ = appState.iosAudio?.isSuppressingForPlayback
            _ = appState.iosAudio?.status
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.track()
                self.observe()
            }
        }
    }

    private func track() {
        let now = ProcessInfo.processInfo.systemUptime
        let t = now - startedAt

        if let status = appState.iosAudio?.status, status != lastStatus {
            lastStatus = status
            write(SessionLogFormat.statusLine(t: t, status: status))
        }
        if let gate = appState.iosAudio?.isSuppressingForPlayback, gate != lastGate {
            lastGate = gate
            write(SessionLogFormat.gateLine(t: t, closed: gate))
        }

        let note = appState.display.note
        let midi = note?.midiNote
        if midi != lastNoteMIDI {
            let previous = lastNoteMIDI
            lastNoteMIDI = midi
            write(SessionLogFormat.noteLine(
                t: t,
                note: note,
                confidence: appState.display.confidence,
                level: appState.display.level
            ))
            if let midi, midi != previous {
                notesConfirmed += 1
                pitchClasses.insert(((midi % 12) + 12) % 12)
                if let onset = onsetSince {
                    onsetLatencies.append(now - onset)
                    onsetSince = nil
                }
            }
        }

        let chordName = appState.chordDisplay.chord?.name
        if chordName != lastChordName {
            lastChordName = chordName
            write(SessionLogFormat.chordLine(t: t, chord: chordName))
        }

        trackLevel(appState.display.level, now: now)
    }

    /// Onset = the gated level rising above the running noise floor + 6 dB;
    /// it is the cheap worker-level proxy for a pick attack.
    private func trackLevel(_ level: Float, now: Double) {
        let floor = currentNoiseFloor()
        let threshold = floor * pow(10, 6.0 / 20.0)
        let isAbove = level > threshold
        if isAbove && !lastLevelAboveThreshold {
            onsetSince = now
        }
        lastLevelAboveThreshold = isAbove
        lastLevel = level
        if level <= threshold {
            silentLevels.append(level)
            if silentLevels.count > 64 { silentLevels.removeFirst() }
        }
    }

    private func currentNoiseFloor() -> Float {
        guard !silentLevels.isEmpty else { return 0.001 }
        return BleedProbeAnalysis.medianLevel(silentLevels)
    }

    private func logSummary() {
        let median = onsetLatencies.isEmpty ? nil : BleedProbeAnalysis.median(onsetLatencies)
        let p90 = onsetLatencies.isEmpty ? nil : BleedProbeAnalysis.p90(onsetLatencies)
        write(SessionLogFormat.summaryLine(
            notes: notesConfirmed,
            distinctPitchClasses: pitchClasses.count,
            onsetMedian: median,
            onsetP90: p90,
            noiseFloor: currentNoiseFloor()
        ))
    }

    private func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
#endif
