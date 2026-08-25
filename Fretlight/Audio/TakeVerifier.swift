#if DEBUG
import Foundation

/// Why a recorded take was or was not accepted into the library.
enum TakeVerdict: Sendable, Equatable {
    case accepted(frequency: Double, cents: Double)
    /// A mis-fret, or a string that has drifted over a long session.
    case wrongPitch(cents: Double)
    /// Nothing periodic enough to call a pitch — a dead note, or a buzz.
    case noStablePitch
    case tooQuiet
}

/// Judges one recorded take against the position it was meant to be, and
/// prepares an accepted one for the library.
///
/// This is the whole reason the library is recorded inside the app rather than
/// in a DAW: a mis-fretted or buzzed take looks entirely normal in a waveform,
/// and is caught here while the player is still holding the guitar.
enum TakeVerifier {
    /// A pluck's first tens of milliseconds are inharmonic — the pick noise
    /// and the string's initial transverse chaos — and yield no stable period.
    /// 50 ms clears that while leaving several clean periods even on the low E,
    /// whose fundamental is only ~82 Hz.
    static let attackSkipSeconds = 0.05

    /// How much of the sustain to actually analyse. YIN is O(maxTau × window),
    /// so handing it a whole six-second take costs two hundred million float
    /// operations to answer a question that 4096 samples — roughly seven
    /// periods of the lowest note in range — settles just as well.
    static let analysisWindow = 4096

    /// Stricter than `PitchDetector.defaultThreshold` (0.12), which is tuned
    /// for live display where missing a note is worse than a wrong one. Here
    /// the trade is reversed: a take is cheap to redo and expensive to ship
    /// wrong, so only clean periodicity counts as a pitch at all. This is what
    /// separates a buzzed or dead note from a good one.
    static let verificationThreshold: Float = 0.08

    /// Ten cents accepts ordinary intonation and fretting-hand pressure while
    /// still rejecting a true mis-fret, which is a hundred cents out.
    static let centsWindow = 10.0

    /// How much silence to leave ahead of the transient, so every sample in
    /// the library starts the same distance before its attack.
    static let preOnsetSeconds = 0.015

    /// Roughly -30 dBFS. Beneath this a DI take carries more noise than note
    /// and any pitch decision would be led by the noise.
    static let minimumPeak: Float = 0.0316

    /// Roughly -1.9 dBFS. Leaves headroom for the playback chain while
    /// removing accidental pick-force variance between takes.
    static let normalizedPeak: Float = 0.8

    static func verify(_ take: SampleRecorder.Take, string: Int, fret: Int) -> TakeVerdict {
        precondition(Tunings.standard.openMIDINotes.indices.contains(string), "string index out of range")
        guard take.peak >= minimumPeak else { return .tooQuiet }

        let skip = Int(take.sampleRate * attackSkipSeconds)
        guard take.samples.count > skip else { return .noStablePitch }
        let sustained = Array(take.samples[skip..<min(skip + analysisWindow, take.samples.count)])
        guard sustained.count >= 256 else { return .noStablePitch }

        guard let detection = PitchDetector().detect(
            samples: sustained,
            sampleRate: take.sampleRate,
            threshold: verificationThreshold
        ) else { return .noStablePitch }

        let targetMIDI = Tunings.standard.openMIDINotes[string] + fret
        let target = 440.0 * pow(2, Double(targetMIDI - 69) / 12)
        let cents = 1200 * log2(detection.frequency / target)
        guard abs(cents) <= centsWindow else { return .wrongPitch(cents: cents) }
        return .accepted(frequency: detection.frequency, cents: cents)
    }

    /// Cuts the dead air ahead of the transient down to `preOnsetSeconds`.
    static func trimmed(_ take: SampleRecorder.Take) -> SampleRecorder.Take {
        let onsetLevel = max(take.peak * 0.05, minimumPeak)
        guard let onset = take.samples.firstIndex(where: { abs($0) >= onsetLevel }) else { return take }
        let start = max(0, onset - Int(take.sampleRate * preOnsetSeconds))
        guard start > 0 else { return take }
        let samples = Array(take.samples[start...])
        return SampleRecorder.Take(samples: samples, sampleRate: take.sampleRate, peak: peak(of: samples))
    }

    /// Scales to a common peak. Ratios between samples are untouched, so this
    /// changes level and nothing else.
    static func normalized(_ take: SampleRecorder.Take) -> SampleRecorder.Take {
        guard take.peak >= minimumPeak else { return take }
        let scale = normalizedPeak / take.peak
        return SampleRecorder.Take(
            samples: take.samples.map { $0 * scale },
            sampleRate: take.sampleRate,
            peak: normalizedPeak
        )
    }

    private static func peak(of samples: [Float]) -> Float {
        samples.reduce(0) { Swift.max($0, abs($1)) }
    }
}
#endif
