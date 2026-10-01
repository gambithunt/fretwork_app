import Foundation

/// A single user-facing 0...1 "sensitivity" dial, mapped to the two actual
/// DSP knobs that affect it, so the UI doesn't have to expose raw detector
/// internals.
///
/// Written from the main actor (the settings slider); read once per
/// detection cycle (~23ms) on `AudioAnalysisWorker`'s own queue. A lock is
/// simple and far cheaper than that read interval needs — this isn't a
/// realtime audio thread, just a background analysis loop.
final class SensitivitySettings: @unchecked Sendable {
    static let defaultValue: Double = 0.5

    private let lock = NSLock()
    private var raw: Double = SensitivitySettings.defaultValue

    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return raw }
        set { lock.lock(); defer { lock.unlock() }; raw = min(max(newValue, 0), 1) }
    }

    /// The external "is this confident enough to actually display" gate
    /// (compared against `PitchDetection.confidence` in AudioAnalysisWorker).
    /// 0.90 at sensitivity 0 (strict — only very clean signals show a note),
    /// 0.66 at sensitivity 1 (lenient — shows notes from weaker/noisier
    /// signal, at the cost of more false triggers). 0.78, the value this was
    /// fixed at before this control existed, falls out at the default 0.5.
    var confidenceThreshold: Float { Float(0.90 - 0.24 * value) }

    /// The YIN detector's own internal CMNDF cutoff (see PitchDetector).
    /// 0.06 at sensitivity 0, 0.18 at sensitivity 1; 0.12 — the detector's
    /// original fixed value — falls out at the default 0.5.
    var yinThreshold: Float { Float(0.06 + 0.12 * value) }

    /// The dB margin a detection's level must clear above the running noise
    /// floor before it can be displayed (compared in AudioAnalysisWorker).
    /// 13 dB at sensitivity 0 (strict — only notes clearly above room noise
    /// show), 7 dB at sensitivity 1 (lenient — very quiet notes show, at the
    /// cost of more room noise). Folded into the same dial as the confidence
    /// and YIN knobs, so there is still one user control. The margin sits a
    /// little lower than a pure level cut because the pitch-stability rule
    /// already rejects gliding room noise, letting weak but steady strings
    /// through.
    var floorMarginDb: Double { 13 - 6 * value }

    /// The confidence a *continuation* frame needs while the same note is
    /// already confirmed. Lower than `confidenceThreshold`, so a decaying
    /// note is held instead of dropping to "none" the moment confidence dips;
    /// a changed pitch re-enters at the full `confidenceThreshold`, so a real
    /// note change is not delayed.
    var sustainConfidenceThreshold: Float { confidenceThreshold - 0.15 }
}
