import SwiftUI

/// A running log of distinct things the player has just played — chords in
/// Chords mode, notes in Notes mode — most recent last. Tapping a chip pins
/// it onto the fretboard in place of the live feed; tapping the same chip
/// again releases it. Generic over the entry type so both modes share one
/// component instead of two near-identical views.
///
/// Spread edge-to-edge with spacers between chips rather than packed to the
/// leading edge in a horizontal scroll: the history is capped (see
/// `AppState.chordHistoryLimit`/`noteHistoryLimit`), and the window's own
/// minimum width comfortably fits that many chips, so there's no case where
/// this actually needs to scroll — packing them left just left most of the
/// row visibly unused.
struct HistoryStrip<Entry: Identifiable>: View where Entry.ID == UUID {
    let history: [Entry]
    let pinnedID: UUID?
    let label: (Entry) -> String
    let tint: (Entry) -> Color
    /// What's being held, for the tap-to-hold help text — "chord"/"note".
    let noun: String
    let onSelect: (UUID?) -> Void

    var body: some View {
        // Collapses to nothing on a fresh session rather than showing an
        // empty track — there's nothing useful to fill the row with yet.
        if !history.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                    chip(entry)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    if index < history.count - 1 {
                        Spacer(minLength: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            // The oldest chip falls off the front the moment the cap is
            // exceeded (see `AppState.appending`), which without an explicit
            // animation would just pop out of existence on the next redraw.
            // Keying on the id sequence (not just count) means this also
            // fires for the ordinary case of a chip fading in at the end.
            .animation(.easeInOut(duration: 0.32), value: history.map(\.id))
        }
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
