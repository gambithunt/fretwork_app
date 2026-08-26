import SwiftUI

/// One marker on the board.
///
/// The learning modules layer boards on top of each other — a focused
/// pentatonic box over its quieter neighbours, chord tones over the rest of a
/// scale — so a dot carries more than a position and a label: it carries how
/// prominent it should be. Everything past `color` has a default, so a simple
/// board states only what it cares about.
struct FretboardDot: Identifiable, Equatable {
    /// The size the detection board's markers have always been drawn at.
    /// Named because the label font keys off it — see `FretboardDotView`.
    static let defaultRadius: CGFloat = 15.5

    /// Stable across layouts. The board animates a dot from its old position
    /// to its new one when the same id reappears, so an id that changes with
    /// the content turns a slide into a cross-fade.
    let id: String
    let position: FretPosition
    let label: String
    let color: Color

    /// For layered views, where the focused box sits full size over recessed
    /// neighbours. The default is the size the detection board's markers have
    /// always been drawn at.
    var radius: CGFloat = FretboardDot.defaultRadius
    var alpha: Double = 1
    /// A halo, for marking a root without changing the dot's own colour.
    var ring: Color?
    var ringAlpha: Double = 1
    /// A dark separating outline, so overlapping tiers stay legible.
    var outline: Bool = false
    /// The dot's own edge. Present by default because that is how this app has
    /// always drawn a note marker; a layered view that would rather its
    /// recessed dots had no edge sets it to nil.
    var stroke: Color? = .white.opacity(0.85)
    var labelColor: Color = .white
    /// What this dot is in context — "root", "3rd" — for the legend and for
    /// the accessible description. Not drawn.
    var role: String?
}
