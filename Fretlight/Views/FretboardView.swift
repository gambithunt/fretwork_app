import SwiftUI

struct FretboardView: View {
    let note: MappedNote?
    /// Every position the note could be played at, the resolver's pick first.
    /// All of them are drawn identically for now: the ranking is computed and
    /// carried here, but not yet expressed visually.
    let positions: [RankedPosition]
    private let frets = 22
    private var activeMarkers: [ActiveFretMarker] {
        guard let note else { return [] }
        return positions.sorted {
            $0.position.string == $1.position.string
                ? $0.position.fret < $1.position.fret
                : $0.position.string < $1.position.string
        }
        .map { ActiveFretMarker(noteMIDI: note.midiNote, position: $0.position) }
    }

    var body: some View {
        Canvas { context, size in
            let labels: CGFloat = 62
            let board = CGRect(x: labels, y: 34, width: size.width - labels, height: size.height - 38)
            let panel = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: panel, cornerRadius: 14),
                with: .color(Color(red: 0.085, green: 0.085, blue: 0.105))
            )
            context.fill(
                Path(roundedRect: board, cornerRadius: 7),
                with: .color(Color(red: 0.115, green: 0.115, blue: 0.14))
            )
            for fret in 0...frets {
                let x = board.minX + board.width * CGFloat(fret) / CGFloat(frets)
                var line = Path(); line.move(to: CGPoint(x: x, y: board.minY)); line.addLine(to: CGPoint(x: x, y: board.maxY))
                context.stroke(line, with: .color(fret == 0 ? .white.opacity(0.32) : .white.opacity(0.09)), lineWidth: fret == 0 ? 2 : 1)
                // Fret numbers describe the space after each fret wire, so
                // position them at the centre of that space rather than on
                // the wire itself. The open-string label remains by the nut.
                let labelX = fret == 0
                    ? board.minX + 9
                    : board.minX + board.width * (CGFloat(fret) - 0.5) / CGFloat(frets)
                context.draw(Text("\(fret)").font(.caption2.monospacedDigit()).foregroundColor(.white.opacity(0.42)), at: CGPoint(x: labelX, y: 13))
            }
            for fret in [3, 5, 7, 9, 15, 17, 19, 21] {
                let x = board.minX + board.width * (CGFloat(fret) - 0.5) / CGFloat(frets)
                let dot = CGRect(x: x - 4, y: board.midY - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.22)))
            }
            for fret in [12] {
                let x = board.minX + board.width * (CGFloat(fret) - 0.5) / CGFloat(frets)
                for y in [board.midY - 24, board.midY + 24] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.22)))
                }
            }
            for string in 0..<6 {
                let y = board.minY + board.height * (CGFloat(string) + 0.5) / 6
                context.draw(Text(GuitarTuning.stringNames[string]).font(.caption.weight(.medium)).foregroundColor(.white.opacity(0.62)), at: CGPoint(x: 25, y: y))
                var line = Path(); line.move(to: CGPoint(x: board.minX, y: y)); line.addLine(to: CGPoint(x: board.maxX, y: y))
                context.stroke(line, with: .color(.white.opacity(0.16)), lineWidth: 0.8 + CGFloat(string) * 0.16)
            }
        }
        .overlay {
            GeometryReader { proxy in
                let labels: CGFloat = 62
                let board = CGRect(x: labels, y: 34, width: proxy.size.width - labels, height: proxy.size.height - 38)
                let stringSpacing = board.height / 6
                ForEach(activeMarkers) { marker in
                    if let note {
                        let position = marker.position
                        let x = position.fret == 0 ? board.minX + 14 : board.minX + board.width * (CGFloat(position.fret) - 0.5) / CGFloat(frets)
                        let targetY = board.minY + board.height * (CGFloat(position.string) + 0.5) / 6
                        // The display runs Low E at the top through High E at
                        // the bottom. Treble strings (G, B, High E — index 3
                        // and up) enter from the string immediately above and
                        // slide down into place, then retreat back up when
                        // they disappear; bass strings (Low E, A, D) do the
                        // opposite. Each marker's start/end Y is computed as
                        // an absolute position (not an offset layered on top
                        // of a separately-fixed position), so the two ends of
                        // the animation are exactly one string apart with
                        // nothing else able to pull it toward the board's
                        // center.
                        let startY = position.string >= 3 ? targetY - stringSpacing : targetY + stringSpacing
                        NoteMarker(note: note)
                            .transition(markerTransition(x: x, targetY: targetY, startY: startY))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: note?.midiNote)
        .accessibilityLabel("Twenty-two fret guitar fretboard")
    }

    private func markerTransition(x: CGFloat, targetY: CGFloat, startY: CGFloat) -> AnyTransition {
        .modifier(
            active: MarkerMotionModifier(x: x, y: startY, scale: 0.66, opacity: 0),
            identity: MarkerMotionModifier(x: x, y: targetY, scale: 1, opacity: 1)
        )
    }
}

private struct ActiveFretMarker: Identifiable {
    let noteMIDI: Int
    let position: FretPosition

    var id: String { "\(noteMIDI)-\(position.string)-\(position.fret)" }
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

private struct NoteMarker: View {
    let note: MappedNote
    private var tint: Color { NotePalette.color(for: note.name) }
    var body: some View {
        Text("\(note.name)\(note.octave)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 31, height: 31)
            .background(tint, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
            .shadow(color: tint.opacity(0.65), radius: 8)
    }
}
