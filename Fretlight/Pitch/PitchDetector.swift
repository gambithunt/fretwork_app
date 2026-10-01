import Foundation
import Accelerate

struct PitchDetection: Sendable { let frequency: Double; let confidence: Float }

/// YIN needs several waveform periods. At 48 kHz, a 2048-sample window means
/// low E's practical detection latency is bounded at roughly 25–40 ms by physics.
final class PitchDetector: @unchecked Sendable {
    private var difference: [Float]
    private var cmndf: [Float]
    private var scratch: [Float]

    /// The CMNDF cutoff below which a tau is accepted as period-like.
    /// Lower is stricter (only very clean periodicity counts, fewer false
    /// positives on noisy signals); higher is more lenient (catches weaker
    /// or noisier signals, at the cost of more false positives). 0.12
    /// matches the detector's original fixed behavior.
    static let defaultThreshold: Float = 0.12

    /// The effective cutoff for a given tau. It rises toward the low-frequency
    /// end of the tau range (large tau = low pitch): a real low string decays
    /// fast and carries little fundamental energy, so its CMNDF at the true
    /// period sits higher than a fixed cutoff would admit — measured on an
    /// unplugged electric where low E/A sat at CMNDF ≈ 0.15–0.16 against the
    /// 0.12 default and produced no candidate at all, while the same pickup
    /// produced clean candidates the moment the cutoff passed ~0.16. The boost
    /// is linear in tau so high pitches keep the strict cutoff. Downstream,
    /// `confidence` gating and the noise-floor-relative level gate decide
    /// whether the extra low-frequency candidates are displayed.
    private static func cutoff(forTau tau: Int, base: Float, maxTau: Int) -> Float {
        base * (1 + 0.6 * Float(tau) / Float(maxTau))
    }

    init(maxWindowSize: Int = 2048) {
        difference = .init(repeating: 0, count: maxWindowSize / 2 + 1)
        cmndf = .init(repeating: 0, count: maxWindowSize / 2 + 1)
        scratch = .init(repeating: 0, count: maxWindowSize)
    }

    func detect(samples: [Float], sampleRate: Double, threshold: Float = PitchDetector.defaultThreshold) -> PitchDetection? {
        let count = samples.count
        guard count >= 256, sampleRate > 0 else { return nil }
        let maxTau = min(count / 2, Int(sampleRate / 65))
        let minTau = max(2, Int(sampleRate / 1_100))
        guard maxTau > minTau else { return nil }
        if difference.count <= maxTau { difference = .init(repeating: 0, count: maxTau + 1); cmndf = difference }
        // `scratch` holds one lag's worth of differences — `count - tau`
        // elements — so it is sized by the *window*, not by `maxTau`. It used
        // to be resized only inside the branch above, which left it at its
        // initial capacity for any window larger than `maxWindowSize` while
        // `vDSP_vsub` below wrote `count - tau` floats into it. The only
        // caller passes exactly 2048 against a 2048-element buffer — one
        // element under the limit — which is the only reason this never
        // corrupted the heap.
        if scratch.count < count { scratch = .init(repeating: 0, count: count) }

        difference[0] = 0
        samples.withUnsafeBufferPointer { source in
            for tau in 1...maxTau {
                let n = vDSP_Length(count - tau)
                vDSP_vsub(source.baseAddress! + tau, 1, source.baseAddress!, 1, &scratch, 1, n)
                var sum: Float = 0
                vDSP_svesq(scratch, 1, &sum, n)
                difference[tau] = sum
            }
        }
        cmndf[0] = 1
        var running: Float = 0
        for tau in 1...maxTau {
            running += difference[tau]
            cmndf[tau] = running > 0 ? difference[tau] * Float(tau) / running : 1
        }
        var tau = minTau
        while tau < maxTau && cmndf[tau] >= Self.cutoff(forTau: tau, base: threshold, maxTau: maxTau) { tau += 1 }
        guard tau < maxTau else { return nil }
        while tau + 1 <= maxTau && cmndf[tau + 1] < cmndf[tau] { tau += 1 }
        let left = cmndf[tau - 1], center = cmndf[tau], right = cmndf[tau + 1]
        let denominator = left - 2 * center + right
        let refined = Double(tau) + (abs(denominator) > .leastNonzeroMagnitude ? Double(0.5 * (left - right) / denominator) : 0)
        let confidence = max(0, min(1, 1 - center))
        guard refined > 0 else { return nil }
        return PitchDetection(frequency: sampleRate / refined, confidence: confidence)
    }
}
