import SwiftUI

/// The general fretboard: a neck plus whatever dots you hand it.
///
/// Dots are matched between layouts by `id`, so changing a selection slides
/// the dots that survive into their new positions and fades only genuine
/// additions and removals. That is why `FretboardDot.id` has to be stable
/// across a change — an id derived from the content turns every slide into a
/// cross-fade, which reads as the board being rebuilt rather than moving.
struct FretboardBoardView: View {
    let dots: [FretboardDot]
    var frets: Int = 22
    var tuning: Tuning = Tunings.standard
    var flipped: Bool = false
    var margins: BoardGeometry.Margins = .labelled
    var showsLabels: Bool = true
    /// Per-dot emphasis, 0...1, driven by playback so what is heard and what
    /// lights up cannot drift apart.
    var pulses: [String: Double] = [:]

    /// Matches the detection board's existing motion, so a module board and
    /// the listening screen feel like the same instrument.
    private static let motion = Animation.spring(response: 0.32, dampingFraction: 0.7)

    var body: some View {
        BoardCanvas(frets: frets, tuning: tuning, flipped: flipped, margins: margins, showsLabels: showsLabels)
            .overlay {
                GeometryReader { proxy in
                    let geometry = BoardGeometry(
                        size: proxy.size,
                        frets: frets,
                        strings: tuning.openMIDINotes.count,
                        flipped: flipped,
                        margins: margins
                    )
                    ForEach(dots) { dot in
                        FretboardDotView(dot: dot, pulse: pulses[dot.id] ?? 0)
                            .position(geometry.point(dot.position))
                            // Appearing and disappearing dots scale from the
                            // position they belong at rather than sliding in
                            // from elsewhere — a note that was not there has
                            // no previous position to have come from.
                            .transition(.scale(scale: 0.66).combined(with: .opacity))
                    }
                }
                .allowsHitTesting(false)
            }
            .animation(Self.motion, value: dots)
    }
}

/// One dot. Every visual property comes from the model rather than from the
/// board, because the layered modules need dots of different weights on the
/// same neck at the same time.
struct FretboardDotView: View {
    let dot: FretboardDot
    var pulse: Double = 0

    /// How far a pulse grows the dot. Enough to read across a room without
    /// the dot colliding with its neighbours at the tightest fret spacing.
    private static let pulseGrowth: CGFloat = 0.28

    var body: some View {
        let diameter = dot.radius * 2 * (1 + Self.pulseGrowth * CGFloat(pulse))
        Text(dot.label)
            .font(.system(size: dot.radius * 0.62, weight: .bold))
            .foregroundStyle(dot.labelColor)
            .frame(width: diameter, height: diameter)
            .background(dot.color, in: Circle())
            .overlay {
                if dot.outline {
                    // Only where tiers overlap. On a single-layer board this
                    // would just muddy the dot's own edge.
                    Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1.5)
                }
            }
            .overlay {
                if let ring = dot.ring {
                    Circle()
                        .strokeBorder(ring.opacity(dot.ringAlpha), lineWidth: 2)
                        .padding(-3)
                }
            }
            .opacity(dot.alpha)
    }
}
