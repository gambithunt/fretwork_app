import SwiftUI

/// A running log of distinct things the player has just played — chords in
/// Chords mode, notes in Notes mode — most recent last. Tapping a chip pins
/// it onto the fretboard in place of the live feed; tapping the same chip
/// again releases it. Generic over the entry type so both modes share one
/// component instead of two near-identical views.
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
        // empty track — there's nothing useful to scroll through yet.
        if !history.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(spacing: 8) {
                        ForEach(history) { entry in
                            chip(entry)
                        }
                    }
                    // Keeps the newest entry in view as the log grows,
                    // without the player having to scroll to see what they
                    // just played.
                    .onChange(of: history.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(history.last?.id, anchor: .trailing)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(history.last?.id, anchor: .trailing)
                    }
                }
            }
            .frame(height: 40)
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
        .id(entry.id)
        .help(isPinned ? "Showing this \(noun)'s shape — tap again to follow live" : "Hold this \(noun)'s shape on the fretboard")
    }
}
