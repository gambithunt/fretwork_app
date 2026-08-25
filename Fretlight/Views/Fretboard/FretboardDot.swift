import SwiftUI

/// One marker on the board.
///
/// The learning modules layer boards on top of each other — a focused
/// pentatonic box over its quieter neighbours, chord tones over the rest of a
/// scale — so a dot carries more than a position and a label: it carries how
/// prominent it should be. Everything past `color` has a default, so a simple
/// board states only what it cares about.
struct FretboardDot: Identifiable, Equatable {
    /// Stable across layouts. The board animates a dot from its old position
    /// to its new one when the same id reappears, so an id that changes with
    /// the content turns a slide into a cross-fade.
    let id: String
    let position: FretPosition
    let label: String
    let color: Color

    /// For layered views, where the focused box sits full size over recessed
    /// neighbours.
    var radius: CGFloat = 12
    var alpha: Double = 1
    /// A halo, for marking a root without changing the dot's own colour.
    var ring: Color?
    var ringAlpha: Double = 1
    /// A dark separating outline, so overlapping tiers stay legible.
    var outline: Bool = false
    var labelColor: Color = .white
    /// What this dot is in context — "root", "3rd" — for the legend and for
    /// the accessible description. Not drawn.
    var role: String?
}
