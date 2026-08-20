import SwiftUI

/// A running log of distinct chords the player has strummed, most recent
/// last. Tapping a chip pins its chord onto the fretboard in place of the
/// live feed; tapping the same chip again releases it. Purely a display of
/// `AppState.chordHistory` — all dedup/cap bookkeeping happens there.
struct ChordHistoryStrip: View {
    let history: [ChordHistoryEntry]
    let pinnedID: UUID?
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
                    // Keeps the newest chord in view as the log grows,
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

    private func chip(_ entry: ChordHistoryEntry) -> some View {
        let isPinned = entry.id == pinnedID
        return Button {
            onSelect(isPinned ? nil : entry.id)
        } label: {
            Text(entry.match.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(NotePalette.color(for: entry.match.root), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(.white.opacity(isPinned ? 0.9 : 0), lineWidth: 2)
                )
                .opacity(isPinned ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .id(entry.id)
        .help(isPinned ? "Showing this chord's shape — tap again to follow live" : "Hold this chord's shape on the fretboard")
    }
}
