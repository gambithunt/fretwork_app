import Foundation

/// Pure, hardware-free computations for the Phase 7 speaker-bleed probe.
///
/// Everything here takes value-type series and returns numbers, so the two
/// decisions the probe rests on — "when has the mic fallen back to the noise
/// floor *and* the detector gone silent" and "did the detector credit the
/// played pitch class, for how long" — are unit-testable without an
/// `AVAudioSession`, a graph or a device. That is the same rule 007's execution
/// contract point 4 applies to every detection-adjacent decision in this repo.
enum BleedProbeAnalysis {

    /// One level reading from the analysis worker: linear RMS and the wall
    /// time it was taken (monotonic, in seconds).
    struct LevelReading: Sendable, Equatable {
        var time: Double
        var level: Float
    }

    /// One note-detector reading: the reported MIDI note, or nil when the
    /// detector is silent on that update.
    struct NoteReading: Sendable, Equatable {
        var time: Double
        var midiNote: Int?
    }

    /// One chord-detector reading: the reported chord name, or nil when
    /// silent.
    struct ChordReading: Sendable, Equatable {
        var time: Double
        var name: String?
    }

    /// A detector-active reading, collapsed from whichever detector governs a
    /// leg (notes for single notes, chords for the strummed chord): true when
    /// that detector reported a result on that update.
    struct ActiveReading: Sendable, Equatable {
        var time: Double
        var active: Bool
    }

    /// Linear level in dBFS-ish terms (floor at -120 dB), for log lines.
    static func levelDB(_ level: Float) -> Double {
        20 * log10(max(Double(level), 0.000_001))
    }

    /// The linear level that is `noiseFloor + 3 dB` — the threshold the mic
    /// must fall back under for the decay tail to end.
    static func tailThreshold(noiseFloor: Float) -> Float {
        noiseFloor * pow(10, 3.0 / 20.0)
    }

    /// The decay tail: how long after `nominalEnd` both conditions hold — the
    /// mic level is at or below `noiseFloor + 3 dB`, and the governing
    /// detector has gone silent.
    ///
    /// Defined as the *last* time either condition is violated, minus
    /// `nominalEnd` (clamped to ≥ 0): the tail is over once both have settled
    /// and neither re-appears later in the recorded window. Using the last
    /// violation rather than the first passing sample makes the result robust
    /// to one stray loud frame or one late detector blip after an otherwise
    /// clean settle.
    static func decayTail(
        noiseFloor: Float,
        levelReadings: [LevelReading],
        activeReadings: [ActiveReading],
        nominalEnd: Double
    ) -> Double {
        let threshold = tailThreshold(noiseFloor: noiseFloor)
        var lastViolation = nominalEnd
        for reading in levelReadings where reading.time >= nominalEnd && reading.level > threshold {
            lastViolation = max(lastViolation, reading.time)
        }
        for reading in activeReadings where reading.time >= nominalEnd && reading.active {
            lastViolation = max(lastViolation, reading.time)
        }
        return max(0, lastViolation - nominalEnd)
    }

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

    /// Median of a level series, used as the noise-floor estimate so one
    /// loud transient in the silence window cannot inflate it.
    static func medianLevel(_ levels: [Float]) -> Float {
        medianOf(levels)
    }

    /// Median of a tail series, for the probe's summary line.
    static func median(_ values: [Double]) -> Double {
        medianOf(values)
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

    /// Shared stepwise sum: each matching reading is credited from its own
    /// time until the next reading in the (sorted) series, or `to`.
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
