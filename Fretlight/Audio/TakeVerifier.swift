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

    /// Was 0.08 — deliberately stricter than `PitchDetector.defaultThreshold`
    /// (0.12), on the reasoning that a take is cheap to redo and expensive to
    /// ship wrong. That reasoning was sound and the number was not: it was
    /// picked against sine waves, which are perfectly periodic. A real string
    /// — especially a wound low E, whose fundamental is the weakest partial on
    /// many pickups — does not reach 0.08, so good takes were being called
    /// unpitched.
    ///
    /// Now matched to the live detector. If the app trusts this much
    /// periodicity to put a note on screen, it can trust it to accept a take;
    /// a genuinely dead or buzzed note still fails it.
    static let verificationThreshold: Float = PitchDetector.defaultThreshold

    /// Was 10 cents, which is a studio tuner's tolerance rather than a
    /// guitar's. A real instrument is out by more than that from fretting
    /// pressure alone, before intonation error up the neck is counted. 25
    /// still leaves three quarters of a semitone of margin before a genuine
    /// mis-fret — a hundred cents — could slip through, which is the error
    /// this is actually here to catch.
    static let centsWindow = 25.0

    /// How much silence to leave ahead of the transient, so every sample in
    /// the library starts the same distance before its attack.
    static let preOnsetSeconds = 0.015

    /// Roughly -40 dBFS. Beneath this a DI take carries more noise than note
    /// and any pitch decision would be led by the noise. Was -30 dBFS, which
    /// assumed an input driven harder than a clean DI usually is.
    static let minimumPeak: Float = 0.01

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

    /// What the verifier actually saw, whatever it decided.
    ///
    /// A rejection with no numbers behind it is untriageable: "wrong pitch"
    /// and "wrong by exactly an octave" want completely different fixes, and
    /// "no stable pitch" could mean a dead note or merely a threshold set too
    /// strict for a real string. Every constant here was chosen against
    /// synthesised sine waves, so the first real session needs to be able to
    /// see past the verdict.
    static func diagnostics(_ take: SampleRecorder.Take, string: Int, fret: Int) -> String {
        guard Tunings.standard.openMIDINotes.indices.contains(string) else { return "invalid string" }
        let targetMIDI = Tunings.standard.openMIDINotes[string] + fret
        let target = 440.0 * pow(2, Double(targetMIDI - 69) / 12)

        var parts = [String(format: "peak %.3f (min %.3f)", take.peak, minimumPeak)]

        let skip = Int(take.sampleRate * attackSkipSeconds)
        guard take.samples.count > skip else {
            parts.append("too short to analyse (\(take.samples.count) frames)")
            return parts.joined(separator: " · ")
        }
        let sustained = Array(take.samples[skip..<min(skip + analysisWindow, take.samples.count)])
        parts.append(String(format: "%.2fs", Double(take.samples.count) / take.sampleRate))

        // Run at both thresholds. If the strict one finds nothing and the
        // live detector's looser one finds the right pitch, the take is fine
        // and the strictness is the problem — which is the single most likely
        // way sine-tuned constants fail on a real string.
        let detector = PitchDetector()
        let strict = detector.detect(samples: sustained, sampleRate: take.sampleRate, threshold: verificationThreshold)
        let loose = detector.detect(samples: sustained, sampleRate: take.sampleRate, threshold: PitchDetector.defaultThreshold)

        parts.append(String(format: "target %.1f Hz", target))
        parts.append(describe(strict, target: target, label: "strict \(verificationThreshold)"))
        parts.append(describe(loose, target: target, label: "loose \(PitchDetector.defaultThreshold)"))
        return parts.joined(separator: " · ")
    }

    private static func describe(_ detection: PitchDetection?, target: Double, label: String) -> String {
        guard let detection else { return "\(label): none" }
        let cents = 1200 * log2(detection.frequency / target)
        return String(format: "%@: %.1f Hz %+.0f¢ conf %.2f", label, detection.frequency, cents, detection.confidence)
    }

    private static func peak(of samples: [Float]) -> Float {
        samples.reduce(0) { Swift.max($0, abs($1)) }
    }
}
#endif
