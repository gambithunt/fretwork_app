import Foundation

/// Pure, hardware-free computations for the Phase 7 speaker-bleed probe.
///
/// Everything here takes value-type series and returns numbers, so the
/// decisions the probe rests on — how long after a sample's nominal end the
/// detectors keep reporting, whether the detector credited the *played* pitch
/// class / chord, which other pitch classes showed up — are unit-testable
/// without an `AVAudioSession`, a graph or a device. That is the same rule
/// 007's execution contract point 4 applies to every detection-adjacent
/// decision in this repo.
enum BleedProbeAnalysis {

    /// One level reading from the analysis worker: linear RMS and the wall
    /// time it was taken (monotonic, in seconds).
    struct LevelReading: Sendable, Equatable {
        var time: Double
        var level: Float
    }

    /// One note-detector reading. `confidence` is the worker's published
    /// confidence, which is nonzero **only** when the detector produced a
    /// fresh result above the production `sensitivity.confidenceThreshold` —
    /// during the worker's 180 ms display hold it is 0 while `midiNote` stays
    /// non-nil. That makes `confidence > 0` exactly "reported a note with
    /// confidence above the production threshold".
    struct NoteReading: Sendable, Equatable {
        var time: Double
        var midiNote: Int?
        var confidence: Float
    }

    /// One chord-detector reading: the reported chord name, or nil when
    /// silent. Non-nil already implies the chord detector's own confidence
    /// floor was met.
    struct ChordReading: Sendable, Equatable {
        var time: Double
        var name: String?
    }

    /// Linear level in dBFS-ish terms (floor at -120 dB), for log lines.
    static func levelDB(_ level: Float) -> Double {
        20 * log10(max(Double(level), 0.000_001))
    }

    /// The level reading nearest `time`, in dB — context for the log, never
    /// a gate criterion.
    static func levelDB(near time: Double, in readings: [LevelReading]) -> Double? {
        guard let nearest = readings.min(by: { abs($0.time - time) < abs($1.time - time) }) else { return nil }
        return levelDB(nearest.level)
    }

    // MARK: - Detector-based tail (the gate's input)

    /// Seconds after `nominalEnd` of the last note reading, within
    /// `[nominalEnd, gapEnd]`, that reported **any** note with confidence
    /// above the production threshold. Nil when none did.
    static func lastDetectionAfterEnd(
        readings: [NoteReading],
        nominalEnd: Double,
        gapEnd: Double
    ) -> Double? {
        let last = readings
            .filter { $0.time >= nominalEnd && $0.time <= gapEnd && $0.confidence > 0 }
            .map(\.time)
            .max()
        return last.map { max(0, $0 - nominalEnd) }
    }

    /// Seconds after `nominalEnd` of the last fresh reading, within
    /// `[nominalEnd, gapEnd]`, that reported a note whose *pitch class* is one
    /// of `playedPitchClasses` (mod 12, so any octave counts).
    static func lastPlayedPitchAfterEnd(
        playedPitchClasses: Set<Int>,
        readings: [NoteReading],
        nominalEnd: Double,
        gapEnd: Double
    ) -> Double? {
        let last = readings
            .filter { reading in
                guard reading.time >= nominalEnd, reading.time <= gapEnd, reading.confidence > 0,
                      let midi = reading.midiNote else { return false }
                return playedPitchClasses.contains(((midi % 12) + 12) % 12)
            }
            .map(\.time)
            .max()
        return last.map { max(0, $0 - nominalEnd) }
    }

    /// Seconds after `nominalEnd` of the last chord-worker detection (non-nil
    /// chord) within `[nominalEnd, gapEnd]`.
    static func lastChordDetectionAfterEnd(
        readings: [ChordReading],
        nominalEnd: Double,
        gapEnd: Double
    ) -> Double? {
        let last = readings
            .filter { $0.time >= nominalEnd && $0.time <= gapEnd && $0.name != nil }
            .map(\.time)
            .max()
        return last.map { max(0, $0 - nominalEnd) }
    }

    /// Distinct pitch classes (as MIDI note-number mod 12), freshly detected
    /// at any point in `[from, to]`, that are **not** in `playedPitchClasses`
    /// — harmonics and misreads. Sorted ascending.
    static func otherPitchClasses(
        playedPitchClasses: Set<Int>,
        readings: [NoteReading],
        from: Double,
        to: Double
    ) -> [Int] {
        var seen = Set<Int>()
        for reading in readings where reading.time >= from && reading.time <= to && reading.confidence > 0 {
            guard let midi = reading.midiNote else { continue }
            let pitchClass = ((midi % 12) + 12) % 12
            if !playedPitchClasses.contains(pitchClass) { seen.insert(pitchClass) }
        }
        return seen.sorted()
    }

    // MARK: - False credit (played pitch class / chord name)

    /// How long the note detector reported a note whose *pitch class* is one
    /// of `playedPitchClasses` (mod 12, so any octave of the played note
    /// counts — the app would credit its own speaker either way). Each
    /// matching reading is held until the next reading in the series (or
    /// `to`), because that is when evidence replaced it.
    static func falseCreditDuration(
        playedPitchClasses: Set<Int>,
        readings: [NoteReading],
        from: Double,
        to: Double
    ) -> Double {
        heldDuration(
            readings.sorted { $0.time < $1.time },
            from: from,
            to: to,
            time: { $0.time },
            matches: { reading in
                guard let midi = reading.midiNote else { return false }
                return playedPitchClasses.contains(((midi % 12) + 12) % 12)
            }
        )
    }

    /// How long the chord detector reported the played chord by name.
    static func chordFalseCreditDuration(
        playedChordName: String,
        readings: [ChordReading],
        from: Double,
        to: Double
    ) -> Double {
        heldDuration(
            readings.sorted { $0.time < $1.time },
            from: from,
            to: to,
            time: { $0.time },
            matches: { $0.name == playedChordName }
        )
    }

    // MARK: - Summary statistics

    /// Median of a level series, used as the noise-floor estimate so one
    /// loud transient in the silence window cannot inflate it.
    static func medianLevel(_ levels: [Float]) -> Float {
        medianOf(levels)
    }

    /// Median of a duration series, for the probe's summary line.
    static func median(_ values: [Double]) -> Double {
        medianOf(values)
    }

    /// Interpolated 90th percentile (the standard `rank = 0.9 * (n - 1)`
    /// linear interpolation over the sorted series).
    static func p90(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let rank = 0.9 * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        let fraction = rank - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }

    private static func medianOf<T: BinaryFloatingPoint & Comparable>(_ values: [T]) -> T {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    // MARK: - Shared stepwise sum

    /// Each matching reading is credited from its own time until the next
    /// reading in the (sorted) series, or `to`.
    private static func heldDuration<T>(
        _ readings: [T],
        from: Double,
        to: Double,
        time: (T) -> Double,
        matches: (T) -> Bool
    ) -> Double {
        var total = 0.0
        for index in readings.indices {
            let readingTime = time(readings[index])
            guard readingTime >= from, readingTime <= to else { continue }
            guard matches(readings[index]) else { continue }
            let next = index + 1 < readings.count ? min(time(readings[index + 1]), to) : to
            total += max(0, next - readingTime)
        }
        return total
    }
}
