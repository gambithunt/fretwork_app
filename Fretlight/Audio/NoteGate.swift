import Foundation

/// The pure per-frame gate decision behind `AudioAnalysisWorker`'s consume
/// loop, kept as a function so the confidence, sustain and noise-floor rules
/// can be pinned by unit tests without standing up the ring, queue and
/// wall-clock throttling. The worker layers the pitch-stability rule for new
/// notes on top of these three booleans.
enum NoteGate {
    struct Decision: Equatable {
        /// True when the candidate continues the currently confirmed note
        /// (within ±1 semitone); continuations use the relaxed confidence
        /// floor and are exempt from the level gate.
        let isContinuation: Bool
        /// Confidence passed the full gate (new/changed) or the relaxed
        /// sustain gate (continuation).
        let confidencePasses: Bool
        /// Level cleared the running noise floor plus margin. Always true for
        /// continuations, which are level-exempt.
        let levelPasses: Bool
    }

    static func decide(
        candidateMIDI: Int?,
        confidence: Float,
        lastMIDI: Int?,
        levelDb: Double,
        floorDb: Double,
        sensitivity: SensitivitySettings
    ) -> Decision {
        guard let candidateMIDI else { return Decision(isContinuation: false, confidencePasses: false, levelPasses: false) }
        let isContinuation = lastMIDI.map { abs(candidateMIDI - $0) <= 1 } ?? false
        let requiredConfidence = isContinuation ? sensitivity.sustainConfidenceThreshold : sensitivity.confidenceThreshold
        let confidencePasses = confidence > requiredConfidence
        let levelPasses = isContinuation || levelDb > floorDb + sensitivity.floorMarginDb
        return Decision(isContinuation: isContinuation, confidencePasses: confidencePasses, levelPasses: levelPasses)
    }
}
