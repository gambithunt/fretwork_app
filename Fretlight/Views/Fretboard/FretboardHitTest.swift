import CoreGraphics

/// What a touch on the board landed on.
///
/// Split out from the gesture that produced it so the decision — which is the
/// part with rules — can be tested directly. The gesture layer then only has
/// to report a point.
enum FretboardHit: Equatable {
    /// A dot already on the board. The module decides what that means: the
    /// Notes screen sounds it, others may select it.
    case dot(FretboardDot)
    /// A playable position with nothing on it.
    case cell(FretPosition)
}

enum FretboardHitTest {
    /// Resolves a point to whatever occupies that cell.
    ///
    /// Cell-first rather than nearest-dot: the board is a grid of playable
    /// positions, and a tap between two dots means the cell it fell in, not
    /// whichever dot happens to be closest. Nearest-dot matching would make
    /// an empty cell beside a dot un-tappable, which is exactly the gesture
    /// the Notes screen needs in order to place a note.
    static func resolve(
        location: CGPoint,
        geometry: BoardGeometry,
        frets: Int,
        dots: [FretboardDot]
    ) -> FretboardHit? {
        guard let position = geometry.position(at: location, frets: frets) else { return nil }
        // Last wins, so a dot drawn on top of another — which the layered
        // module views do deliberately — is the one a tap reports.
        if let dot = dots.last(where: { $0.position == position }) {
            return .dot(dot)
        }
        return .cell(position)
    }
}
