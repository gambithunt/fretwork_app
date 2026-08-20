import SwiftUI

/// A running log of distinct things the player has just played — chords in
/// Chords mode, notes in Notes mode — most recent last. Tapping a chip pins
/// it onto the fretboard in place of the live feed; tapping the same chip
/// again releases it. Generic over the entry type so both modes share one
/// component instead of two near-identical views.
///
/// Chips are spread edge-to-edge across the available width with spacers,
/// not packed to the leading edge — the caps (`AppState.chordHistoryLimit`/
/// `noteHistoryLimit`) are sized so real-world sequences fit without
/// scrolling, so packing them left just left most of the row visibly
/// unused. The `ScrollView` wrapper stays as a fallback, not the primary
/// interaction: a pathological run of the longest possible labels can still
/// overflow the measured budget, and scrolling gracefully beats clipping.
struct HistoryStrip<Entry: Identifiable>: View where Entry.ID == UUID {
    let history: [Entry]
    let pinnedID: UUID?
    let label: (Entry) -> String
    let tint: (Entry) -> Color
    /// What's being held, for the tap-to-hold help text — "chord"/"note".
    let noun: String
    let onSelect: (UUID?) -> Void
    let onClear: () -> Void

    var body: some View {
        // The row is reserved whether or not there is anything in it. It used
        // to collapse to nothing on a fresh session, which meant the first
        // note played shoved the fretboard down — and since the strip fills
        // within seconds of playing, the empty state it was optimising for is
        // the one nobody spends any time in. An empty track costs a blank
        // 40pt; a board that jumps under the player's eyes costs more.
        ZStack(alignment: .leading) {
            Color.clear
            if !history.isEmpty {
                strip
            }
        }
        .frame(height: 40)
    }

    private var strip: some View {
        HStack(spacing: 8) {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                                chip(entry)
                                    // Its own animation, so the newcomer is
                                    // not locked to the curve the rest of the
                                    // row moves on — see the row animation
                                    // below. Asymmetric on purpose: an
                                    // arrival is an event and lands with a
                                    // spring, a departure is bookkeeping and
                                    // just goes.
                                    .transition(
                                        .asymmetric(
                                            insertion: .scale(scale: 0.62).combined(with: .opacity)
                                                .animation(.spring(response: 0.26, dampingFraction: 0.58)),
                                            removal: .opacity.animation(.easeOut(duration: 0.12))
                                        )
                                    )
                                if index < history.count - 1 {
                                    Spacer(minLength: 8)
                                }
                            }
                        }
                        // Pinning the row's content to at least the full
                        // viewport width is what lets the spacers above
                        // actually spread the chips edge-to-edge when
                        // everything fits; content narrower than this would
                        // otherwise just hug the leading edge inside the
                        // ScrollView the way it did before.
                        .frame(minWidth: proxy.size.width, alignment: .leading)
                    }
                    // The oldest chip falls off the front the moment the cap
                    // is exceeded (see `AppState.appending`), which without
                    // an explicit animation would just pop out of existence
                    // on the next redraw. Keying on the id sequence (not
                    // just count) also covers the ordinary case of a chip
                    // fading in at the end.
                    //
                    // Sprung and delayed, because this is where the strip's
                    // visual mass actually is. Chips are spread by count, so
                    // once the cap is reached every arrival slides the whole
                    // row one slot — a far bigger movement than the chip's
                    // own. Under the single flat curve this used to share
                    // with the newcomer, everything moved together at the
                    // same speed and nothing read as landing. Letting the
                    // arrival lead by a beat and the row follow with a little
                    // overshoot is what makes it read as weight rather than
                    // as a reflow. Kept short: entries can arrive ~90ms apart
                    // (`AppState.noteHistorySettle`), and motion that outlasts
                    // the gap between notes turns a fast passage into mush.
                    .animation(.spring(response: 0.3, dampingFraction: 0.68).delay(0.05), value: history.map(\.id))
                }
                clearButton
        }
    }

    private var clearButton: some View {
        Button(action: onClear) {
            Image(systemName: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .controlSize(.small)
        .help("Clear \(noun) history")
    }

    private func chip(_ entry: Entry) -> some View {
        let isPinned = entry.id == pinnedID
        // The newest entry sits at full strength and dims to the resting 0.72
        // when the next one supersedes it. A chip used to arrive already
        // dimmed, which is the opposite of an arrival having weight — and
        // this doubles as a "you are here" marker without inventing any new
        // visual language for it.
        let isNewest = entry.id == history.last?.id
        return Button {
            onSelect(isPinned ? nil : entry.id)
        } label: {
            Text(label(entry))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(tint(entry), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(.white.opacity(isPinned ? 0.9 : 0), lineWidth: 2)
                )
                .opacity(isPinned || isNewest ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Showing this \(noun)'s shape — tap again to follow live" : "Hold this \(noun)'s shape on the fretboard")
    }
}
