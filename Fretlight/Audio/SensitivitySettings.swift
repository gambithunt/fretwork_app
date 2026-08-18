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
}
