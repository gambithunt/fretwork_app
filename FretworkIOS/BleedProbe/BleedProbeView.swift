#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only, launch-argument-gated (`-FretworkBleedProbe`) speaker-bleed
/// measurement for Phase 7 (C-05). Runs unattended on the physical iPhone,
/// writes every result line to stderr for `devicectl … --console`, and prints
/// "BLEED-PROBE DONE" when finished.
///
/// It drives the production `IOSAudioController` directly — the same
/// capture+output session, the same `playSample` path, the same `NoteSequencer`
/// strum the Chords module uses — and taps **both** the gated `onEvent` stream
/// (what `AppState` sees, through the playback gate) and the raw
/// `onRawWorkerUpdate` stream (ungated worker output), so a rerun with the
/// gate on can report `falseCreditsGated=0` while the raw numbers still show
/// the acoustic truth. It never opens a second `RingBuffer` reader (that would
/// corrupt the SPSC read cursor) and never builds its own graph.
struct BleedProbeView: View {
    var body: some View {
        Text("Speaker-bleed probe running — see the console (stderr).")
            .font(.body)
            .padding()
            .task {
                // The run is unattended and ~2 minutes long; auto-lock would
                // end the audio session mid-leg.
                UIApplication.shared.isIdleTimerDisabled = true
                await BleedProbeRunner().run()
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}

/// The unattended measurement itself. `@MainActor` because `IOSAudioController`
/// is; the only waiting is `Task.sleep`, so nothing here blocks the main actor
/// and no realtime block is created.
@MainActor
private final class BleedProbeRunner {

    /// The production audio controller, exactly as `AppState+IOS` builds it.
    private let controller = IOSAudioController()
    /// Kept alive while the strummed chord's sequencer runs.
    private var chordsModel: ChordsModuleModel?

    /// Raw (ungated) worker outputs, recorded from `onRawWorkerUpdate`.
    private var rawLevelReadings: [BleedProbeAnalysis.LevelReading] = []
    private var rawNoteReadings: [BleedProbeAnalysis.NoteReading] = []
    private var rawChordReadings: [BleedProbeAnalysis.ChordReading] = []

    /// Gated worker outputs, recorded from `onEvent` — the stream AppState sees.
    private var gatedNoteReadings: [BleedProbeAnalysis.NoteReading] = []
    private var gatedChordReadings: [BleedProbeAnalysis.ChordReading] = []

    private var noiseFloor: Float = 0

    /// How long after a sample's nominal end the probe keeps recording. This
    /// doubles as the gap between samples (≥ 8 s, so the previous sample's
    /// detector tail can never run into the next sample's window).
    private static let postRollSeconds = 8.0

    private struct Leg {
        let label: String
        let string: Int
        let fret: Int
        let duration: Double
        let playedPitchClasses: Set<Int>
        let isChord: Bool
        let playedChordName: String?
    }

    private struct LegMetrics {
        var firstDetection: Double?
        var falseCredit: Bool
        var falseCreditS: Double
        var lastAfterEnd: Double?
        var lastPlayedAfterEnd: Double?
        var otherPitches: [Int]
        var maxLevel: Float
    }

    private struct LegResult {
        let gatedLastAfterEnd: Double?
        let gatedFalseCredit: Bool
        let rawFalseCredit: Bool
        let rawOtherPitches: [Int]
        let summary: String
    }

    func run() async {
        log("BLEED-PROBE START device=\(UIDevice.current.model) os=\(UIDevice.current.systemVersion)")
        controller.onEvent = { [weak self] event in self?.recordGated(event) }
        controller.onRawWorkerUpdate = { [weak self] event in self?.recordRaw(event) }
        controller.setChordDetectionEnabled(true)
        // The app usually hears `didBecomeActive` first; at launch the probe's
        // task can race past it, so assert the foreground state the system is
        // about to deliver anyway. Idempotent if the notification already ran.
        controller.setForegroundActive(true)

        guard controller.start() else {
            log("BLEED-PROBE ABORT microphone-permission-denied")
            log("BLEED-PROBE DONE")
            return
        }

        let libraryLoaded = await prepareLibrary()
        guard libraryLoaded else {
            log("BLEED-PROBE ABORT sample-library-load-failed")
            log("BLEED-PROBE DONE")
            return
        }

        guard await waitUntilListening() else {
            log("BLEED-PROBE ABORT never-listening status=\(statusDescription(controller.status))")
            log("BLEED-PROBE DONE")
            return
        }

        await recordNoiseFloor(seconds: 3)
        log("BLEED-PROBE noiseFloor=\(String(format: "%.5f", noiseFloor)) db=\(String(format: "%.1f", BleedProbeAnalysis.levelDB(noiseFloor)))")

        let legs = makeLegs()
        guard !legs.isEmpty else {
            log("BLEED-PROBE ABORT no-legs")
            log("BLEED-PROBE DONE")
            return
        }

        var results: [LegResult] = []
        for leg in legs {
            let result = await runLeg(leg)
            log(result.summary)
            results.append(result)
        }

        let gatedLastAfterEnds = results.map { $0.gatedLastAfterEnd ?? 0 }
        let maxGated = gatedLastAfterEnds.max() ?? 0
        let p90Gated = BleedProbeAnalysis.p90(gatedLastAfterEnds)
        let falseCreditsGated = results.filter { $0.gatedFalseCredit }.count
        let falseCreditsRaw = results.filter { $0.rawFalseCredit }.count
        let otherPitchMisreadsRaw = results.filter { !$0.rawOtherPitches.isEmpty }.count
        log("BLEED-PROBE SUMMARY maxLastDetectionAfterEndGated=\(String(format: "%.3f", maxGated)) p90LastDetectionAfterEndGated=\(String(format: "%.3f", p90Gated)) falseCreditsGated=\(falseCreditsGated)/\(legs.count) falseCreditsRaw=\(falseCreditsRaw)/\(legs.count) otherPitchMisreadsRaw=\(otherPitchMisreadsRaw)/\(legs.count)")
        log("BLEED-PROBE DONE")
    }

    // MARK: - Setup phases

    private func prepareLibrary() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            controller.prepareSamplePlayback { _ in
                continuation.resume()
            }
        }
        return controller.isSampleLibraryLoaded
    }

    private func waitUntilListening() async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while ProcessInfo.processInfo.systemUptime < deadline {
            if controller.status == .listening, controller.isSamplePlaybackReady {
                return true
            }
            if case .failed = controller.status { return false }
            if controller.status == .permissionDenied { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func recordNoiseFloor(seconds: Double) async {
        clearRecordings()
        try? await Task.sleep(for: .seconds(seconds))
        noiseFloor = BleedProbeAnalysis.medianLevel(rawLevelReadings.map(\.level))
    }

    // MARK: - The legs

    private func makeLegs() -> [Leg] {
        guard let library = controller.sampleLibraryForTesting else { return [] }

        func duration(_ string: Int, _ fret: Int) -> Double {
            guard let sample = library.sample(string: string, fret: fret) else { return 0 }
            return Double(sample.frameCount) / sample.sampleRate
        }
        func noteLeg(_ label: String, _ string: Int, _ fret: Int) -> Leg {
            let midi = Tunings.standard.openMIDINotes[string] + fret
            let pitchClass = ((midi % 12) + 12) % 12
            return Leg(
                label: label,
                string: string,
                fret: fret,
                duration: duration(string, fret),
                playedPitchClasses: [pitchClass],
                isChord: false,
                playedChordName: nil
            )
        }

        var legs: [Leg] = [
            noteLeg("low-E-open", 0, 0),
            noteLeg("A2", 1, 0),
            noteLeg("D3", 2, 0),
            noteLeg("G3", 3, 0),
            noteLeg("B3", 4, 0),
            noteLeg("high-e-open", 5, 0),
            noteLeg("12th-fret-E3", 0, 12),
            noteLeg("17th-fret-A5", 5, 17),
        ]

        // The quiet leg: only when the shipped library genuinely varies in
        // level (≥ ~3 dB between its quietest and loudest takes).
        var quietest: (string: Int, fret: Int, peak: Float)?
        var loudestPeak: Float = 0
        for sample in library.samples {
            let base = library.audio(for: sample)
            var peak: Float = 0
            for index in 0..<sample.frameCount { peak = max(peak, abs(base[index])) }
            if peak > loudestPeak { loudestPeak = peak }
            if quietest == nil || peak < quietest!.peak {
                quietest = (sample.string, sample.fret, peak)
            }
        }
        if let quietest, quietest.peak > 0, loudestPeak / quietest.peak >= 1.41 {
            legs.append(noteLeg("quiet-\(quietest.string)-\(quietest.fret)", quietest.string, quietest.fret))
            log("BLEED-PROBE quietLeg=\(quietest.string):\(quietest.fret) peak=\(String(format: "%.4f", quietest.peak)) loudestPeak=\(String(format: "%.4f", loudestPeak))")
        } else {
            log("BLEED-PROBE quietLeg=skipped (no ≥3 dB gain variation)")
        }

        // The strummed chord: C major open voicing, through the production
        // sequencer path the Chords module uses.
        let positions = (ChordVoicings.voicings(root: PitchClass(0), formulaID: "maj").first?.frets ?? [])
            .enumerated()
            .compactMap { string, fret in fret.map { FretPosition(string: string, fret: $0) } }
        if !positions.isEmpty {
            var chordDuration = 0.0
            var pitchClasses = Set<Int>()
            for (index, position) in positions.enumerated() {
                let offset = NoteSequencer.strumOffset * Double(index)
                let midi = Tunings.standard.openMIDINotes[position.string] + position.fret
                pitchClasses.insert(((midi % 12) + 12) % 12)
                chordDuration = max(chordDuration, offset + duration(position.string, position.fret))
            }
            legs.append(Leg(
                label: "chord-C-major",
                string: -1,
                fret: -1,
                duration: chordDuration,
                playedPitchClasses: pitchClasses,
                isChord: true,
                playedChordName: "C"
            ))
        }

        return legs
    }

    private func runLeg(_ leg: Leg) async -> LegResult {
        clearRecordings()

        let start = ProcessInfo.processInfo.systemUptime
        let nominalEnd = start + leg.duration
        let windowEnd = nominalEnd + Self.postRollSeconds

        if leg.isChord {
            playChord()
        } else {
            controller.playSample(string: leg.string, fret: leg.fret, tuning: Tunings.standard)
        }
        log("BLEED-PROBE leg=\(leg.label) duration=\(String(format: "%.3f", leg.duration))")

        try? await Task.sleep(for: .seconds(leg.duration + Self.postRollSeconds))
        // Let the last in-flight worker update (≤ ~33 ms) land on the main actor.
        try? await Task.sleep(for: .milliseconds(250))

        let gated = analyze(
            leg,
            noteReadings: gatedNoteReadings,
            chordReadings: gatedChordReadings,
            levelReadings: rawLevelReadings,
            start: start,
            nominalEnd: nominalEnd,
            windowEnd: windowEnd
        )
        let raw = analyze(
            leg,
            noteReadings: rawNoteReadings,
            chordReadings: rawChordReadings,
            levelReadings: rawLevelReadings,
            start: start,
            nominalEnd: nominalEnd,
            windowEnd: windowEnd
        )

        let summary = buildSummary(leg, gated: gated, raw: raw, nominalEnd: nominalEnd)

        return LegResult(
            gatedLastAfterEnd: gated.lastAfterEnd,
            gatedFalseCredit: gated.falseCredit,
            rawFalseCredit: raw.falseCredit,
            rawOtherPitches: raw.otherPitches,
            summary: summary
        )
    }

    private func analyze(
        _ leg: Leg,
        noteReadings: [BleedProbeAnalysis.NoteReading],
        chordReadings: [BleedProbeAnalysis.ChordReading],
        levelReadings: [BleedProbeAnalysis.LevelReading],
        start: Double,
        nominalEnd: Double,
        windowEnd: Double
    ) -> LegMetrics {
        let inWindow: (Double) -> Bool = { $0 >= start && $0 <= windowEnd }
        let maxLevel = levelReadings.filter { inWindow($0.time) }.map(\.level).max() ?? 0

        var firstDetection: Double?
        var falseCreditS = 0.0
        var lastAfterEnd: Double?
        var lastPlayedAfterEnd: Double?
        var otherPitches: [Int] = []

        if leg.isChord, let playedChordName = leg.playedChordName {
            if let first = chordReadings.first(where: { inWindow($0.time) && $0.name != nil }) {
                firstDetection = first.time - start
            }
            falseCreditS = BleedProbeAnalysis.chordFalseCreditDuration(
                playedChordName: playedChordName,
                readings: chordReadings,
                from: start,
                to: windowEnd
            )
            lastAfterEnd = BleedProbeAnalysis.lastChordDetectionAfterEnd(
                readings: chordReadings,
                nominalEnd: nominalEnd,
                gapEnd: windowEnd
            )
        } else {
            if let first = noteReadings.first(where: { inWindow($0.time) && $0.midiNote != nil }) {
                firstDetection = first.time - start
            }
            falseCreditS = BleedProbeAnalysis.falseCreditDuration(
                playedPitchClasses: leg.playedPitchClasses,
                readings: noteReadings,
                from: start,
                to: windowEnd
            )
            lastAfterEnd = BleedProbeAnalysis.lastDetectionAfterEnd(
                readings: noteReadings,
                nominalEnd: nominalEnd,
                gapEnd: windowEnd
            )
            lastPlayedAfterEnd = BleedProbeAnalysis.lastPlayedPitchAfterEnd(
                playedPitchClasses: leg.playedPitchClasses,
                readings: noteReadings,
                nominalEnd: nominalEnd,
                gapEnd: windowEnd
            )
            otherPitches = BleedProbeAnalysis.otherPitchClasses(
                playedPitchClasses: leg.playedPitchClasses,
                readings: noteReadings,
                from: start,
                to: windowEnd
            )
        }

        return LegMetrics(
            firstDetection: firstDetection,
            falseCredit: falseCreditS > 0,
            falseCreditS: falseCreditS,
            lastAfterEnd: lastAfterEnd,
            lastPlayedAfterEnd: lastPlayedAfterEnd,
            otherPitches: otherPitches,
            maxLevel: maxLevel
        )
    }

    private func buildSummary(_ leg: Leg, gated: LegMetrics, raw: LegMetrics, nominalEnd: Double) -> String {
        func fields(_ label: String, _ m: LegMetrics) -> String {
            var s = "\(label).firstDetection=\(fmt(m.firstDetection))"
                + " \(label).falseCredit=\(m.falseCredit ? "yes" : "no")"
                + " \(label).falseCreditS=\(String(format: "%.3f", m.falseCreditS))"
            if leg.isChord {
                s += " \(label).lastChordAfterEnd=\(fmt(m.lastAfterEnd))"
            } else {
                s += " \(label).lastDetectionAfterEnd=\(fmt(m.lastAfterEnd))"
                s += " \(label).lastPlayedPitchAfterEnd=\(fmt(m.lastPlayedAfterEnd))"
                let names = m.otherPitches.map { NoteMapper.pitchClassNames[$0] }
                s += " \(label).otherPitches=\(names.isEmpty ? "none" : names.joined(separator: ","))"
            }
            s += " \(label).maxLevelDb=\(String(format: "%.1f", BleedProbeAnalysis.levelDB(m.maxLevel)))"
            return s
        }

        let levelParts: [String] = [0.25, 0.5, 1.0, 2.0, 4.0].compactMap { offset in
            guard let db = BleedProbeAnalysis.levelDB(near: nominalEnd + offset, in: rawLevelReadings) else { return nil }
            return "+\(String(format: "%.2f", offset))s=\(String(format: "%.1f", db))dB"
        }

        return "BLEED-PROBE result=\(leg.label) duration=\(String(format: "%.3f", leg.duration)) "
            + fields("gated", gated) + " " + fields("raw", raw)
            + " levels[\(levelParts.joined(separator: " "))]"
    }

    private func playChord() {
        let model = ChordsModuleModel(play: { [weak self] position in
            self?.controller.playSample(string: position.string, fret: position.fret, tuning: Tunings.standard)
        })
        chordsModel = model
        model.strum()
    }

    // MARK: - Tap and helpers

    private func recordRaw(_ event: AudioControllerEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case .noteUpdate(let display):
            rawLevelReadings.append(.init(time: now, level: display.level))
            rawNoteReadings.append(.init(time: now, midiNote: display.note?.midiNote, confidence: display.confidence))
        case .chordUpdate(let display):
            rawChordReadings.append(.init(time: now, name: display.chord?.name))
        case .error, .recovered, .reconnecting:
            break
        }
    }

    private func recordGated(_ event: AudioControllerEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case .noteUpdate(let display):
            gatedNoteReadings.append(.init(time: now, midiNote: display.note?.midiNote, confidence: display.confidence))
        case .chordUpdate(let display):
            gatedChordReadings.append(.init(time: now, name: display.chord?.name))
        case .error, .recovered, .reconnecting:
            break
        }
    }

    private func clearRecordings() {
        rawLevelReadings.removeAll(keepingCapacity: true)
        rawNoteReadings.removeAll(keepingCapacity: true)
        rawChordReadings.removeAll(keepingCapacity: true)
        gatedNoteReadings.removeAll(keepingCapacity: true)
        gatedChordReadings.removeAll(keepingCapacity: true)
    }

    private func fmt(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? "none"
    }

    private func statusDescription(_ status: IOSAudioStatus) -> String {
        switch status {
        case .idle: "idle"
        case .starting: "starting"
        case .listening: "listening"
        case .interrupted: "interrupted"
        case .permissionDenied: "permissionDenied"
        case .failed(let message): "failed: \(message)"
        }
    }

    private func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

#endif
