import SwiftUI

/// How a board looks while a guided run is playing.
///
/// Ported from `../fretwork/src/lib/guided-presentation.ts`. Shared by every
/// module with guided practice, because the emphasis *is* the instruction: the
/// note to play now is the largest thing on the board and carries the fretting
/// finger rather than its own label, the note after it is visible but recessed
/// so the hand knows where it is going, and everything else dims to context.
///
/// Only applied while actually playing. During the count-in the whole shape
/// stays legible, which is what the count-in is for — reading the shape before
/// the first beat.
enum GuidedPresentation {
    static func decorate(
        _ dots: [FretboardDot],
        steps: [GuidedScaleStep],
        snapshot: GuidedSession<GuidedScaleStep>.Snapshot
    ) -> [FretboardDot] {
        guard snapshot.status == .playing, let index = snapshot.currentIndex else { return dots }
        let currentID = steps.indices.contains(index) ? steps[index].id : nil
        let nextID = steps.indices.contains(index + 1) ? steps[index + 1].id : nil

        return dots.map { dot in
            if let currentID, dot.id == currentID {
                // The finger, not the note name: mid-run the useful information
                // is which finger goes down, and the note name is already in
                // the readout. `label` is a `let`, so the dot is rebuilt rather
                // than mutated — its id is unchanged, which is what keeps the
                // board animating the same dot rather than cross-fading it.
                return FretboardDot(
                    id: dot.id,
                    position: dot.position,
                    label: "\(steps[index].finger.rawValue)",
                    color: dot.color,
                    radius: FretboardDot.defaultRadius,
                    alpha: 1,
                    ring: dot.color,
                    outline: true
                )
            }
            var dot = dot
            if let nextID, dot.id == nextID {
                dot.radius = 13
                dot.alpha = 0.72
                dot.ring = dot.color
                dot.outline = true
            } else {
                dot.alpha = 0.28
            }
            return dot
        }
    }
}
