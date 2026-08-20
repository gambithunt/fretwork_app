import Foundation
import Accelerate

struct ChordMatch: Sendable, Equatable {
    let root: String
    let quality: ChordQuality
    /// Cosine similarity between the observed chroma and the winning
    /// template, 0...1. Not calibrated against real guitar recordings yet —
    /// see the threshold note on `ChordDetector.minimumConfidence`.
    let confidence: Float
    var name: String { root + quality.suffix }
}

enum ChordQuality: String, Sendable, CaseIterable {
    case major, minor, dominantSeventh, majorSeventh, minorSeventh, diminished, augmented, suspendedSecond, suspendedFourth

    /// Semitone offsets from the root that make up this quality.
    var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .dominantSeventh: return [0, 4, 7, 10]
        case .majorSeventh: return [0, 4, 7, 11]
        case .minorSeventh: return [0, 3, 7, 10]
        case .diminished: return [0, 3, 6]
        case .augmented: return [0, 4, 8]
        case .suspendedSecond: return [0, 2, 7]
        case .suspendedFourth: return [0, 5, 7]
        }
    }

    var suffix: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .dominantSeventh: return "7"
        case .majorSeventh: return "maj7"
        case .minorSeventh: return "m7"
        case .diminished: return "dim"
        case .augmented: return "aug"
        case .suspendedSecond: return "sus2"
        case .suspendedFourth: return "sus4"
        }
    }
}

/// Names the chord being played from its pitch-class *content*, unlike
/// `PitchDetector`, which tracks one fundamental. A strummed chord is folded
/// into a 12-bin chromagram (a Fujishima-style pitch class profile: FFT
/// magnitude summed by pitch class, octave collapsed) and matched by cosine
/// similarity against every root/quality template. Chroma is voicing- and
/// octave-invariant by construction, which is exactly what naming a chord
/// wants — a D major reads as "D" whether it's the open-position shape or a
/// barre five frets up.
///
/// Needs a wider window than `PitchDetector`'s 2048 samples: resolving the
/// low E string's chord tones to semitone precision needs finer frequency
/// bins than a fast single-note read does, so this trades latency for
/// resolution deliberately — see `ChordAnalysisWorker`, which runs this at a
/// slower cadence than the note pipeline for exactly that reason.
final class ChordDetector: @unchecked Sendable {
    /// Cosine similarity floor below which no template is treated as a
    /// match. 0.55 is a starting point reasoned from the template geometry
    /// (a clean triad against its own template scores ~0.8-1.0; unrelated
    /// content scores much lower), not measured against a real guitar
    /// signal — per this repo's measurement rule, this needs tuning against
    /// actual strummed recordings (string noise, pick attack, harmonic
    /// smear) before it ships, the same way `SensitivitySettings`' knobs
    /// were.
    static let minimumConfidence: Float = 0.55

    /// Cosine similarity a richer quality (a 7th, an add-tone — anything
    /// with more than 3 chord tones) must beat the *same root's* best
    /// simpler-quality match by, before the richer one is allowed to win.
    ///
    /// Deliberately scoped to "same root" rather than applied as a flat
    /// handicap in the global ranking — an earlier version of this penalty
    /// did that, and it broke genuine 7th-chord detection: a real Gmaj7
    /// (G-B-D-F♯) has a B-minor triad (B-D-F♯) sitting inside it sharing 3
    /// of its 4 notes, and a flat penalty let that unrelated *root* win
    /// outright instead of just downgrading G's own quality. Comparing only
    /// within the winning root avoids that — Bm was never a candidate to
    /// begin with, it just benefited from every other root's templates
    /// being penalized too.
    ///
    /// Richer chords have a structural edge that has nothing to do with
    /// actually being played: a 7th chord's template has a slot for every
    /// triad tone *plus* one more, so any stray energy in that one extra
    /// pitch class gives the 7th template something to "explain" that the
    /// plain triad's template structurally cannot. A real open G major
    /// demonstrated where that stray energy comes from even with zero F♯
    /// actually present: a synthetic *pure* G-B-D triad — no 7th, no
    /// harmonics, nothing but three exact chord-tone sine waves — already
    /// scored G major 0.80 and Gmaj7 0.86 against their own templates. Not
    /// harmonic leakage; frequency-resolution smearing — these are low
    /// guitar notes (98-185 Hz) where this window's bin width (5.86 Hz) is
    /// barely finer than a semitone, so windowing sidelobes blur real
    /// energy into neighboring pitch classes regardless of what's actually
    /// playing. 0.1 clears that measured baseline gap with headroom; still
    /// needs validating against real strummed recordings, same as
    /// `minimumConfidence` — this only rules out the zero-signal case, not
    /// what a real pick attack and string noise add on top.
    static let complexityMargin: Float = 0.1

    /// Guitar's practical range is E2 (82 Hz) up; anything below is room
    /// noise/rumble, not a played note. The ceiling is deliberately low —
    /// ~2 kHz is a handful of harmonics up from the highest open string, and
    /// harmonics further up the series mostly add cross-pitch-class smear
    /// rather than chord information.
    private let minFrequency: Double = 70
    private let maxFrequency: Double = 2_200

    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length
    private let windowSize: Int
    private var real: [Float]
    private var imag: [Float]
    private var hannWindow: [Float]
    private var windowed: [Float]

    /// Every quality rotated through all 12 roots, precomputed once: each
    /// template is a 12-length vector with 1s at `intervals` offset from
    /// `root`, L2-normalized so a plain dot product against a normalized
    /// chroma vector is cosine similarity.
    private let templates: [(root: Int, quality: ChordQuality, vector: [Float])]

    init(windowSize: Int = 8192) {
        precondition(windowSize.nonzeroBitCount == 1, "ChordDetector needs a power-of-two window for the radix-2 FFT")
        self.windowSize = windowSize
        log2n = vDSP_Length(log2(Double(windowSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        real = .init(repeating: 0, count: windowSize / 2)
        imag = .init(repeating: 0, count: windowSize / 2)
        hannWindow = .init(repeating: 0, count: windowSize)
        windowed = .init(repeating: 0, count: windowSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
        templates = ChordQuality.allCases.flatMap { quality in
            (0..<12).map { root in
                var vector = [Float](repeating: 0, count: 12)
                for interval in quality.intervals { vector[(root + interval) % 12] = 1 }
                let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
                return (root, quality, vector.map { $0 / norm })
            }
        }
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// `samples.count` must equal the configured `windowSize`.
    func detect(samples: [Float], sampleRate: Double) -> ChordMatch? {
        guard samples.count == windowSize, sampleRate > 0 else { return nil }
        let chroma = chromagram(of: samples, sampleRate: sampleRate)
        let norm = sqrt(chroma.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        let normalized = chroma.map { $0 / norm }

        // Pass 1: the unbiased raw-score winner across every root and
        // quality — this is what decides the *root*, and nothing below
        // second-guesses that part.
        var best: (root: Int, quality: ChordQuality, score: Float)?
        for template in templates {
            var score: Float = 0
            vDSP_dotpr(normalized, 1, template.vector, 1, &score, 12)
            if best == nil || score > best!.score { best = (template.root, template.quality, score) }
        }
        guard let best, best.score >= Self.minimumConfidence else { return nil }

        // Pass 2: within that same root only, prefer a simpler quality
        // (fewer chord tones) if it scores within `complexityMargin` of the
        // winner — the richer quality's one extra tone isn't clearly
        // present, so default to the smaller chord rather than the one
        // frequency-resolution smear happened to favor. Among qualifying
        // simpler candidates, the best-scoring one wins.
        var simplerBest: (quality: ChordQuality, score: Float)?
        for template in templates where template.root == best.root && template.quality.intervals.count < best.quality.intervals.count {
            var score: Float = 0
            vDSP_dotpr(normalized, 1, template.vector, 1, &score, 12)
            guard score >= best.score - Self.complexityMargin else { continue }
            if simplerBest == nil || score > simplerBest!.score { simplerBest = (template.quality, score) }
        }
        let reportedQuality = simplerBest?.quality ?? best.quality
        let reportedScore = simplerBest?.score ?? best.score
        return ChordMatch(root: NoteMapper.pitchClassNames[best.root], quality: reportedQuality, confidence: reportedScore)
    }

    private func chromagram(of samples: [Float], sampleRate: Double) -> [Float] {
        var chroma = [Float](repeating: 0, count: 12)
        vDSP_vmul(samples, 1, hannWindow, 1, &windowed, 1, vDSP_Length(windowSize))

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { buffer in
                    buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: windowSize / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(windowSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                let binHz = sampleRate / Double(windowSize)
                let minBin = max(1, Int(minFrequency / binHz))
                let maxBin = min(windowSize / 2 - 1, Int(maxFrequency / binHz))
                guard minBin < maxBin else { return }
                for bin in minBin...maxBin {
                    let magnitude = sqrt(realPtr[bin] * realPtr[bin] + imagPtr[bin] * imagPtr[bin])
                    let frequency = Double(bin) * binHz
                    let exactMIDI = 69 + 12 * log2(frequency / 440)
                    let pitchClass = (Int(exactMIDI.rounded()) % 12 + 12) % 12
                    chroma[pitchClass] += magnitude
                }
            }
        }
        return chroma
    }
}
