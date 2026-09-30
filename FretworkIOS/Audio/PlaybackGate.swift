import Foundation

/// Pure timing model for the playback gate: suppress detection from the moment
/// a sample is played until the last scheduled sample's nominal end plus a
/// tail constant.
///
/// No clock lives inside — callers pass `now`, so tests can step time
/// deterministically and the controller never touches a real clock on the
/// audio path. Overlapping plays extend the gate to the latest end, which is
/// exactly what a strum (six `playSample` calls a few ms apart) needs.
struct PlaybackGate: Sendable {

    /// A suppression-state change, returned by `update(at:)`.
    enum Transition: Sendable, Equatable {
        /// The gate just became suppressed (a play landed while open).
        case closed
        /// The gate just lifted (the last sample's end + tail passed).
        case opened
        case none
    }

    /// How long after the last sample's nominal end the gate stays closed.
    let tail: TimeInterval

    /// The end of the current suppression window; nil while the gate is open.
    private(set) var gateEnd: TimeInterval?
    private(set) var suppressed = false

    init(tail: TimeInterval) {
        self.tail = tail
    }

    /// A play dispatched at `now` sounds for `duration` seconds. Later plays
    /// extend `gateEnd` instead of shortening it. Returns the transition this
    /// play produced (`.closed` when it closed an open gate).
    @discardableResult
    mutating func recordPlay(duration: TimeInterval, at now: TimeInterval) -> Transition {
        let end = now + duration + tail
        if gateEnd == nil || end > gateEnd! {
            gateEnd = end
        }
        return update(at: now)
    }

    /// Recomputes suppression at `now`. Returns `.closed` when the gate just
    /// became suppressed, `.opened` when it just lifted, otherwise `.none`.
    ///
    /// The controller reacts to `.opened` by resetting the workers, so a
    /// pre-gate reading cannot leak into the first post-gate update. `suppressed`
    /// is only written on a real transition, so the 30 Hz worker stream does
    /// not invalidate `@Observable` readers (the Playing/L listening pill) on
    /// every frame.
    mutating func update(at now: TimeInterval) -> Transition {
        let nowSuppressed = gateEnd.map { now < $0 } ?? false
        let previous = suppressed
        if nowSuppressed != previous {
            suppressed = nowSuppressed
        }
        if nowSuppressed && !previous { return .closed }
        if !nowSuppressed && previous { return .opened }
        return .none
    }

    var isSuppressed: Bool { suppressed }
}
