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
                                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
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
                    .animation(.easeInOut(duration: 0.32), value: history.map(\.id))
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
                .opacity(isPinned ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Showing this \(noun)'s shape — tap again to follow live" : "Hold this \(noun)'s shape on the fretboard")
    }
}
