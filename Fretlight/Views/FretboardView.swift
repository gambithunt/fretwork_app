import SwiftUI

struct FretboardView: View {
    let note: MappedNote?
    private let frets = 22

    var body: some View {
        Canvas { context, size in
            let labels: CGFloat = 62
            let board = CGRect(x: labels, y: 34, width: size.width - labels, height: size.height - 38)
            context.fill(Path(roundedRect: board, cornerRadius: 8), with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.08, blue: 0.035), Color(red: 0.26, green: 0.13, blue: 0.06)]), startPoint: board.origin, endPoint: CGPoint(x: board.maxX, y: board.maxY)))
            for fret in 0...frets {
                let x = board.minX + board.width * CGFloat(fret) / CGFloat(frets)
                var line = Path(); line.move(to: CGPoint(x: x, y: board.minY)); line.addLine(to: CGPoint(x: x, y: board.maxY))
                context.stroke(line, with: .color(fret == 0 ? .white.opacity(0.85) : .white.opacity(0.23)), lineWidth: fret == 0 ? 5 : 1)
                let labelX = min(max(x, board.minX + 9), board.maxX - 12)
                context.draw(Text("\(fret)").font(.caption2.monospacedDigit()).foregroundColor(.secondary), at: CGPoint(x: labelX, y: 13))
            }
            for fret in [3, 5, 7, 9, 15, 17, 19, 21] {
                let x = board.minX + board.width * (CGFloat(fret) - 0.5) / CGFloat(frets)
                let dot = CGRect(x: x - 4, y: board.midY - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.46)))
            }
            for fret in [12] {
                let x = board.minX + board.width * (CGFloat(fret) - 0.5) / CGFloat(frets)
                for y in [board.midY - 24, board.midY + 24] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.46)))
                }
            }
            for string in 0..<6 {
                let y = board.minY + board.height * (CGFloat(string) + 0.5) / 6
                context.draw(Text(GuitarTuning.stringNames[string]).font(.caption.weight(.medium)), at: CGPoint(x: 25, y: y))
                var line = Path(); line.move(to: CGPoint(x: board.minX, y: y)); line.addLine(to: CGPoint(x: board.maxX, y: y))
                context.stroke(line, with: .color(.white.opacity(0.58)), lineWidth: 1.1 + CGFloat(string) * 0.35)
                for fret in 0...frets where note?.positions.contains(FretPosition(string: string, fret: fret)) == true {
                    let x = fret == 0 ? board.minX + 14 : board.minX + board.width * (CGFloat(fret) - 0.5) / CGFloat(frets)
                    let marker = CGRect(x: x - 15, y: y - 15, width: 30, height: 30)
                    context.fill(Path(ellipseIn: marker), with: .color(.orange))
                    context.stroke(Path(ellipseIn: marker), with: .color(.white.opacity(0.8)), lineWidth: 1)
                    if let note {
                        context.draw(Text("\(note.name)\(note.octave)").font(.caption2.weight(.bold)).foregroundColor(.white), at: CGPoint(x: x, y: y))
                    }
                }
            }
        }
        .accessibilityLabel("Twenty-two fret guitar fretboard")
    }
}
