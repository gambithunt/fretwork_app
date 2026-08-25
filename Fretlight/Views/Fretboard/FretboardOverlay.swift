import SwiftUI

/// An annotation drawn across a set of a board's dots — a box outline around a
/// scale shape, or a line tracing a run of notes in the order they're played.
///
/// This type only says which dots an overlay covers and in what shape; actual
/// drawing is the board's job, not this file's.
struct FretboardOverlay: Identifiable, Equatable, Sendable {
    /// What an overlay's covered dots mean geometrically.
    enum Kind: Equatable, Sendable {
        /// An unordered collection, drawn as one enclosing region (e.g. a
        /// scale box's bounding outline). Membership matters; order doesn't.
        case group
        /// An ordered path, drawn as a line through its dots in sequence
        /// (e.g. a lick or an arpeggio run). The declared order is the
        /// overlay's entire reason for existing.
        case sequence
    }

    let id: String
    let kind: Kind
    let color: Color
    /// The ids of `FretboardDot`s this overlay covers, in the overlay's own
    /// declared order — significant for `.sequence`, incidental for `.group`.
    let dotIDs: [String]

    /// Resolves this overlay's dot ids against the board's actual dots.
    ///
    /// A dot id an overlay names that isn't currently on the board (a scale
    /// shape reaching past a fret count that's since been trimmed, say) is
    /// skipped rather than failing the whole overlay — the rest of the run
    /// still deserves to be drawn.
    ///
    /// For `.sequence` the result walks `dotIDs` in the overlay's own order,
    /// since that order is the path being drawn. For `.group`, resolution
    /// walks `dots` instead: membership is unordered by definition, but the
    /// result still has to be the same list on every call, and looking dots
    /// up by id in a dictionary would depend on hashing order to break ties,
    /// so this keeps `dots`'s own array order rather than reach for a set.
    func resolve(against dots: [FretboardDot]) -> [FretboardDot] {
        switch kind {
        case .sequence:
            // `uniqueKeysWithValues` traps on a duplicate id. Ids are meant
            // to be unique and a duplicate is a bug in whichever module built
            // the dots — but the honest failure for that bug is a misdrawn
            // overlay, not a crashed app, so the first one wins.
            let byID = Dictionary(dots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return dotIDs.compactMap { byID[$0] }
        case .group:
            let wanted = Set(dotIDs)
            return dots.filter { wanted.contains($0.id) }
        }
    }
}
