import Foundation

/// The pure per-frame accept/reject decision behind `AudioAnalysisWorker`'s
/// note gate. Kept as a function rather than inline in the worker so the
/// noise-floor-relative level gate and the sustain rule can be pinned by unit
/// tests without standing up the ring, queue and wall-clock throttling.
enum NoteGate {
    struct Decision: Equatable {
        let accepted: Bool
        /// True when the candidate continues the currently confirmed note
        /// (within ±1 semitone); continuations use the relaxed confidence
        /// floor and are exempt from the level gate, so a decaying note is
        /// held rather than dropped when its level falls.
        let isContinuation: Bool
    }

    static func decide(
        candidateMIDI: Int?,
        confidence: Float,
        lastMIDI: Int?,
        levelDb: Double,
        floorDb: Double,
        sensitivity: SensitivitySettings
    ) -> Decision {
        guard let candidateMIDI else { return Decision(accepted: false, isContinuation: false) }
        let isContinuation = lastMIDI.map { abs(candidateMIDI - $0) <= 1 } ?? false
        let requiredConfidence = isContinuation ? sensitivity.sustainConfidenceThreshold : sensitivity.confidenceThreshold
        let confidencePasses = confidence > requiredConfidence
        let levelPasses = isContinuation || levelDb > floorDb + sensitivity.floorMarginDb
        return Decision(accepted: confidencePasses && levelPasses, isContinuation: isContinuation)
    }
}
