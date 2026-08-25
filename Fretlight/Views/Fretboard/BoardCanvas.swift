import SwiftUI

/// The static instrument: body, inlays, wires, strings and labels.
///
/// Extracted from the detection board so every module draws the same neck.
/// Nothing here knows what is *on* the board — markers are drawn over it by
/// whoever owns them, which is what lets one canvas serve a live detector and
/// a scale diagram without either knowing about the other.
struct BoardCanvas: View {
    /// The frets a real neck marks with inlays. Drawn as a darker bar behind
    /// the whole column rather than as dots of their own — the grid is already
    /// made of dots, so a second kind would just read as noise.
    static let inlayFrets: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21]

    /// Strings and fret wires are drawn at one weight and one opacity so the
    /// board reads as a single grid rather than a set of unrelated rules. The
    /// strings alone taper, because they actually do on the instrument.
    static let lineOpacity: Double = 0.16
    static let fretLineWidth: CGFloat = 1

    let frets: Int
    var tuning: Tuning = Tunings.standard
    var flipped: Bool = false
    var margins: BoardGeometry.Margins = .labelled
    /// Whether to draw the fret numbers and string names. A compact diagram
    /// has no room for them and passes `.none` margins alongside.
    var showsLabels: Bool = true

    var body: some View {
        Canvas { context, size in
            let geometry = BoardGeometry(
                size: size,
                frets: frets,
                strings: tuning.openMIDINotes.count,
                flipped: flipped,
                margins: margins
            )
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
            if showsLabels {
                drawFretNumbers(in: context, geometry: geometry)
                drawStringNames(in: context, geometry: geometry)
            }
            drawGrid(in: context, geometry: geometry)
        }
    }

    /// A darker band filling each marked fret's whole column. Drawn before the
    /// lines so the grid sits on top of it rather than being interrupted by it.
    private func drawInlayBars(in context: GraphicsContext, geometry: BoardGeometry) {
        for fret in Self.inlayFrets where fret <= frets {
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
        guard frets >= 1 else { return }
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
        for string in 0..<geometry.strings {
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
        let names = tuning.stringNames
        for string in 0..<geometry.strings where string < names.count {
            context.draw(
                Text(names[string].uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(1.1)
                    .foregroundColor(.white.opacity(0.55)),
                at: CGPoint(x: 30, y: geometry.y(string: string))
            )
        }
    }

    /// Every playable position as a dot, so the board reads as a full
    /// instrument rather than an empty field waiting for one marker.
    private func drawGrid(in context: GraphicsContext, geometry: BoardGeometry) {
        for fret in 0...frets {
            let x = geometry.x(fret: fret)
            for string in 0..<geometry.strings {
                let dot = CGRect(x: x - 2.5, y: geometry.y(string: string) - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.16)))
            }
        }
    }
}
