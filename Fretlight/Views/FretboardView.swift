import SwiftUI

struct FretboardView: View {
    let mode: DetectionMode
    let note: MappedNote?
    /// Every position the note could be played at, the resolver's pick first.
    /// Only consulted in `.notes` mode.
    let positions: [RankedPosition]
    /// Only consulted in `.chords` mode.
    let chord: ChordMatch?
    /// Display orientation only. `GuitarTuning`'s string indices (0 = Low E
    /// ... 5 = High E) never change; this just tells `BoardGeometry` which
    /// screen row to draw each index at.
    let flipped: Bool
    private let frets = 22
    /// The frets a real neck marks with inlays. Drawn as a darker bar behind
    /// the whole column rather than as dots of their own — the grid is already
    /// made of dots, so a second kind would just read as noise.
    private static let inlayFrets: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21]
    /// Strings and fret wires are drawn at one weight and one opacity so the
    /// board reads as a single grid rather than a set of unrelated rules. The
    /// strings alone taper, because they actually do on the instrument.
    private static let lineOpacity: Double = 0.16
    private static let fretLineWidth: CGFloat = 1

    /// Notes mode marks every place the one detected note could be played,
    /// the resolver's pick first; chords mode marks every open-position
    /// chord tone `ChordShapeResolver` finds, which can be more than one
    /// per string — chroma can't tell which exact voicing was strummed, so
    /// rather than guess one shape this shows every reachable one. Different
    /// sources, same marker so the rest of the view (layout, animation,
    /// drawing) doesn't need to know which mode it's in.
    private var activeMarkers: [ActiveFretMarker] {
        switch mode {
        case .notes:
            guard let note else { return [] }
            return positions.sorted {
                $0.position.string == $1.position.string
                    ? $0.position.fret < $1.position.fret
                    : $0.position.string < $1.position.string
            }
            .map { ActiveFretMarker(id: "\(note.midiNote)-\($0.position.string)-\($0.position.fret)", position: $0.position, label: "\(note.name)\(note.octave)", tint: NotePalette.color(for: note.name)) }
        case .chords:
            guard let chord else { return [] }
            return ChordShapeResolver.fingering(for: chord).map { fingering in
                let label = NoteMapper.pitchClassNames[((fingering.midiNote % 12) + 12) % 12]
                let position = FretPosition(string: fingering.string, fret: fingering.fret)
                return ActiveFretMarker(
                    id: "\(chord.name)-\(fingering.string)-\(fingering.fret)",
                    position: position,
                    label: label,
                    tint: fingering.isRoot ? NotePalette.color(for: chord.root) : .white.opacity(0.4)
                )
            }
        }
    }

    /// What the spring below keys its animation on: a new note in notes
    /// mode, a new chord in chords mode. Unified to `String?` so one
    /// `.animation(value:)` covers both without either mode's identity
    /// leaking into the other's.
    private var animationKey: String? {
        switch mode {
        case .notes: return note.map { String($0.midiNote) }
        case .chords: return chord?.name
        }
    }

    var body: some View {
        Canvas { context, size in
            let geometry = BoardGeometry(size: size, frets: frets, flipped: flipped)
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14),
                with: .color(Color(red: 0.085, green: 0.085, blue: 0.105))
            )
            context.fill(
                Path(roundedRect: geometry.board, cornerRadius: 7),
                with: .color(Color(red: 0.115, green: 0.115, blue: 0.14))
            )
            drawInlayBars(in: context, geometry: geometry)
            drawFrets(in: context, geometry: geometry)
            drawStrings(in: context, geometry: geometry)
            drawFretNumbers(in: context, geometry: geometry)
            drawStringNames(in: context, geometry: geometry)
            drawGrid(in: context, geometry: geometry)
        }
        .overlay {
            GeometryReader { proxy in
                let geometry = BoardGeometry(size: proxy.size, frets: frets, flipped: flipped)
                // Markers in the board's bottom half enter one string closer
                // to center and slide down/outward into their own row, then
                // retreat back toward center when they disappear; markers in
                // the top half do the opposite. Compared against the board's
                // own mid-Y (not a fixed string index) so this still picks
                // the right direction whichever string `flipped` put on top.
                // Each marker's start/end Y is computed as an absolute
                // position (not an offset layered on top of a
                // separately-fixed position), so the two ends of the
                // animation are exactly one string apart with nothing else
                // able to pull it toward the board's center.
                let midY = (geometry.y(string: 0) + geometry.y(string: 5)) / 2
                ForEach(activeMarkers) { marker in
                    let point = geometry.point(marker.position)
                    let startY = point.y > midY
                        ? point.y - geometry.stringSpacing
                        : point.y + geometry.stringSpacing
                    NoteMarker(label: marker.label, tint: marker.tint)
                        .transition(
                            .modifier(
                                active: MarkerMotionModifier(x: point.x, y: startY, scale: 0.66, opacity: 0),
                                identity: MarkerMotionModifier(x: point.x, y: point.y, scale: 1, opacity: 1)
                            )
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: animationKey)
        .accessibilityLabel("Twenty-two fret guitar fretboard")
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        switch mode {
        case .notes:
            guard let note, let pick = positions.first(where: \.isPrimary) else { return "No note detected" }
            let fret = pick.position.fret == 0 ? "open" : "fret \(pick.position.fret)"
            return "\(note.name)\(note.octave), \(GuitarTuning.stringNames[pick.position.string]) string, \(fret)"
        case .chords:
            guard let chord else { return "No chord detected" }
            let shape = ChordShapeResolver.fingering(for: chord).sorted { $0.string < $1.string }
                .map { "\(GuitarTuning.stringNames[$0.string]) \($0.fret == 0 ? "open" : "fret \($0.fret)")" }
                .joined(separator: ", ")
            return "\(chord.name) chord: \(shape)"
        }
    }

    private func drawFretNumbers(in context: GraphicsContext, geometry: BoardGeometry) {
        for fret in 0...frets {
            let marked = Self.inlayFrets.contains(fret)
            context.draw(
                Text("\(fret)")
                    .font(.caption2.monospacedDigit().weight(marked ? .bold : .regular))
                    .foregroundColor(.white.opacity(marked ? 0.75 : 0.34)),
                at: CGPoint(x: geometry.x(fret: fret), y: 13)
            )
        }
    }

    private func drawStringNames(in context: GraphicsContext, geometry: BoardGeometry) {
        for string in 0..<6 {
            context.draw(
                Text(GuitarTuning.stringNames[string].uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(1.1)
                    .foregroundColor(.white.opacity(0.55)),
                at: CGPoint(x: 30, y: geometry.y(string: string))
            )
        }
    }

    /// A darker band filling each marked fret's whole column — the frets a
    /// real neck inlays, 3 through 21. Drawn before the lines so the grid sits
    /// on top of it rather than being interrupted by it.
    private func drawInlayBars(in context: GraphicsContext, geometry: BoardGeometry) {
        for fret in Self.inlayFrets {
            let bar = CGRect(
                x: geometry.leadingEdge(fret: fret),
                y: geometry.board.minY,
                width: geometry.columnWidth,
                height: geometry.board.height
            )
            context.fill(Path(bar), with: .color(.black.opacity(0.30)))
        }
    }

    /// A wire at every fret, including the nut. They sit on the boundaries
    /// between columns, not through them, so each fret's dots stay inside
    /// their own space the way a stopped note sits behind its wire.
    private func drawFrets(in context: GraphicsContext, geometry: BoardGeometry) {
        for fret in 1...frets {
            let x = geometry.leadingEdge(fret: fret)
            var wire = Path()
            wire.move(to: CGPoint(x: x, y: geometry.board.minY))
            wire.addLine(to: CGPoint(x: x, y: geometry.board.maxY))
            context.stroke(wire, with: .color(.white.opacity(Self.lineOpacity)), lineWidth: Self.fretLineWidth)
        }
    }

    /// Weighted low to high: the low E is the thickest string on the
    /// instrument, so it's the heaviest line here.
    private func drawStrings(in context: GraphicsContext, geometry: BoardGeometry) {
        for string in 0..<6 {
            let y = geometry.y(string: string)
            var line = Path()
            line.move(to: CGPoint(x: geometry.board.minX, y: y))
            line.addLine(to: CGPoint(x: geometry.board.maxX, y: y))
            context.stroke(
                line,
                with: .color(.white.opacity(Self.lineOpacity)),
                lineWidth: 1.6 - CGFloat(string) * 0.16
            )
        }
    }

    /// Every playable position as a dot, so the board reads as a full
    /// instrument rather than an empty field waiting for one marker.
    private func drawGrid(in context: GraphicsContext, geometry: BoardGeometry) {
        for fret in 0...frets {
            let x = geometry.x(fret: fret)
            for string in 0..<6 {
                let dot = CGRect(x: x - 2.5, y: geometry.y(string: string) - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.16)))
            }
        }
    }
}

/// Shared by the Canvas and the marker overlay so the two can't drift: every
/// coordinate either of them draws comes from here.
private struct BoardGeometry {
    let board: CGRect
    let columns: Int
    /// When true, string 0 (Low E) draws at the top row and string 5 (High E)
    /// at the bottom — every other draw call routes through `y(string:)` so
    /// this one flag is the entire flip.
    ///
    /// False is the default orientation: Low E at the bottom, matching how the
    /// strings sit when you look down at the instrument in playing position.
    let flipped: Bool

    init(size: CGSize, frets: Int, flipped: Bool) {
        board = CGRect(x: 62, y: 34, width: size.width - 62, height: size.height - 38)
        columns = frets + 1
        self.flipped = flipped
    }

    /// Fret 0 (open) is a column of the grid like any other, rather than a
    /// label tucked against the nut — on a transit map every stop is a stop.
    func x(fret: Int) -> CGFloat {
        board.minX + board.width * (CGFloat(fret) + 0.5) / CGFloat(columns)
    }
    func y(string: Int) -> CGFloat {
        let row = flipped ? string : 5 - string
        return board.minY + board.height * (CGFloat(row) + 0.5) / 6
    }
    func point(_ position: FretPosition) -> CGPoint {
        CGPoint(x: x(fret: position.fret), y: y(string: position.string))
    }
    var stringSpacing: CGFloat { board.height / 6 }
    var columnWidth: CGFloat { board.width / CGFloat(columns) }
    /// Left edge of a fret's column — where its wire sits.
    func leadingEdge(fret: Int) -> CGFloat {
        board.minX + board.width * CGFloat(fret) / CGFloat(columns)
    }
}

private struct ActiveFretMarker: Identifiable {
    let id: String
    let position: FretPosition
    let label: String
    let tint: Color
}

private struct MarkerMotionModifier: ViewModifier {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .position(x: x, y: y)
    }
}

/// Drawn identically regardless of what produced it — every note-mode
/// position the resolver ranks, or every string in a chord's shape. Ranking
/// and root-vs-not both reach the screen only through label/tint and the
/// accessibility value, not through a different marker per case.
private struct NoteMarker: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 31, height: 31)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
    }
}
