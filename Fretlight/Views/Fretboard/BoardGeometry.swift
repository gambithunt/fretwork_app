import CoreGraphics

/// Where every element of a fretboard is drawn.
///
/// Shared by whatever draws the board and whatever draws on top of it, so the
/// two cannot drift: every coordinate either of them uses comes from here.
///
/// Generalised beyond the detection board it started as — string count, fret
/// count and the margins reserved for labels are all parameters — because the
/// learning modules need 12-, 15- and 22-fret boards and the same geometry has
/// to serve all of them.
struct BoardGeometry: Equatable {
    /// Space reserved around the grid for labels drawn outside it.
    struct Margins: Equatable {
        let leading: CGFloat
        let trailing: CGFloat
        let top: CGFloat
        let bottom: CGFloat

        /// What the detection board has always used: a column down the left
        /// for the string names and a row across the top for fret numbers.
        static let labelled = Margins(leading: 62, trailing: 0, top: 34, bottom: 4)

        /// For a board that draws no labels of its own and can use its whole
        /// bounds — a compact chord diagram, say.
        static let none = Margins(leading: 0, trailing: 0, top: 0, bottom: 0)
    }

    let board: CGRect
    let columns: Int
    let strings: Int
    /// When true, string 0 (Low E) draws at the top row and the highest string
    /// at the bottom — every other draw call routes through `y(string:)`, so
    /// this one flag is the entire flip.
    ///
    /// False is the default orientation: Low E at the bottom, high E on top,
    /// matching tablature and the web app's board. True is the player's-eye
    /// view — the neck as it looks from above with the guitar in your hands,
    /// where the low E is the string nearest you.
    let flipped: Bool

    init(size: CGSize, frets: Int, strings: Int = 6, flipped: Bool, margins: Margins = .labelled) {
        board = CGRect(
            x: margins.leading,
            y: margins.top,
            width: max(0, size.width - margins.leading - margins.trailing),
            height: max(0, size.height - margins.top - margins.bottom)
        )
        columns = frets + 1
        self.strings = strings
        self.flipped = flipped
    }

    /// Fret 0 (open) is a column of the grid like any other, rather than a
    /// label tucked against the nut — on a transit map every stop is a stop.
    func x(fret: Int) -> CGFloat {
        board.minX + board.width * (CGFloat(fret) + 0.5) / CGFloat(columns)
    }

    func y(string: Int) -> CGFloat {
        let row = flipped ? string : strings - 1 - string
        return board.minY + board.height * (CGFloat(row) + 0.5) / CGFloat(strings)
    }

    func point(_ position: FretPosition) -> CGPoint {
        CGPoint(x: x(fret: position.fret), y: y(string: position.string))
    }

    /// Halfway between the outermost strings. Used to decide which way a
    /// marker travels as it appears, so the answer stays right whichever
    /// string `flipped` put on top.
    var midY: CGFloat {
        (y(string: 0) + y(string: strings - 1)) / 2
    }

    var stringSpacing: CGFloat { board.height / CGFloat(strings) }
    var columnWidth: CGFloat { board.width / CGFloat(columns) }

    /// Left edge of a fret's column — where its wire sits.
    func leadingEdge(fret: Int) -> CGFloat {
        board.minX + board.width * CGFloat(fret) / CGFloat(columns)
    }

    /// The cell nearest a point, for hit-testing a tap anywhere on the board
    /// rather than only on an existing dot. Nil when the point falls outside
    /// the grid, so a tap in the label gutter is not treated as a note.
    func position(at point: CGPoint, frets: Int) -> FretPosition? {
        guard board.contains(point) else { return nil }
        let column = Int(((point.x - board.minX) / board.width) * CGFloat(columns))
        let row = Int(((point.y - board.minY) / board.height) * CGFloat(strings))
        let fret = min(max(column, 0), frets)
        let clampedRow = min(max(row, 0), strings - 1)
        let string = flipped ? clampedRow : strings - 1 - clampedRow
        return FretPosition(string: string, fret: fret)
    }
}
