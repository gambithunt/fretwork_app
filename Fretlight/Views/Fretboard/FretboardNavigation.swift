import Foundation

/// Arrow-key stepping through an ordered list of anchor positions.
///
/// The web original wires this to a DOM keydown listener; that plumbing has
/// no macOS equivalent, so only the stepping semantics are ported here. A
/// SwiftUI view owns the actual key event and asks this type whether the step
/// happened, so it knows whether to consume the event or let it pass through
/// (e.g. to a surrounding `ScrollView` or window-level shortcut).
struct FretboardNavigation: Sendable {
    /// The ordered stops a step moves between — e.g. the root positions of a
    /// scale's boxes, low to high. Order is significant: `next()` always means
    /// "the next one in this list", not "higher on the neck".
    private(set) var anchors: [FretPosition]
    private(set) var selected: FretPosition?

    init(anchors: [FretPosition], selected: FretPosition? = nil) {
        self.anchors = anchors
        self.selected = selected
    }

    /// Steps back one anchor. Returns whether the selection actually moved.
    ///
    /// A `selected` not present in `anchors` has nothing to count "one step"
    /// from, so it is treated the same as no selection: the step lands on the
    /// first anchor rather than trapping or guessing an offset. That mirrors
    /// what a first arrow-key press should do when nothing is highlighted
    /// yet, and recovers cleanly if the caller's board state and this
    /// navigator's anchor list ever briefly disagree.
    mutating func previous() -> Bool {
        step(by: -1)
    }

    /// Steps forward one anchor. Returns whether the selection actually moved.
    mutating func next() -> Bool {
        step(by: 1)
    }

    private mutating func step(by delta: Int) -> Bool {
        guard !anchors.isEmpty else { return false }
        guard let current = selected, let index = anchors.firstIndex(of: current) else {
            selected = anchors[0]
            return true
        }
        let target = index + delta
        guard anchors.indices.contains(target) else { return false }
        selected = anchors[target]
        return true
    }
}
