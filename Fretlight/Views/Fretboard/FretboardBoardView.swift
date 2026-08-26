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
    /// Annotations drawn beneath the dots — a box around a scale shape, or a
    /// path through a run in the order it is played.
    var overlays: [FretboardOverlay] = []
    /// Interaction is opt-in. A read-only reference board supplies none of
    /// these and stays inert, rather than silently swallowing taps.
    var onHit: ((FretboardHit) -> Void)?
    var onLongPress: ((FretboardHit) -> Void)?

    /// Long enough not to fire on a slow tap, short enough that removing a
    /// note does not feel like waiting.
    private static let longPressDuration = 0.45

    @State private var lastTouch: CGPoint = .zero
    /// A long press also completes as a tap, so without this the same touch
    /// would both remove a note and re-report it.
    @State private var longPressFired = false

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
                    OverlayLayer(overlays: overlays, dots: dots, geometry: geometry)
                    ForEach(dots) { dot in
                        let point = geometry.point(dot.position)
                        // Dots below the board's middle enter one string closer
                        // to centre and settle outward; dots above do the
                        // opposite. Measured against the board's own mid-Y
                        // rather than a fixed string index, so it stays right
                        // whichever string the flip put on top. Both ends are
                        // absolute positions, so they are exactly one string
                        // apart with nothing able to pull them toward centre.
                        let startY = point.y > geometry.midY
                            ? point.y - geometry.stringSpacing
                            : point.y + geometry.stringSpacing
                        FretboardDotView(dot: dot, pulse: pulses[dot.id] ?? 0)
                            // Positioned by the transition's identity state,
                            // not by a separate `.position` on top of it —
                            // applying both places the dot twice and it lands
                            // somewhere neither modifier asked for.
                            .transition(
                                .modifier(
                                    active: DotMotionModifier(x: point.x, y: startY, scale: 0.66, opacity: 0),
                                    identity: DotMotionModifier(x: point.x, y: point.y, scale: 1, opacity: 1)
                                )
                            )
                    }
                }
                .allowsHitTesting(false)
            }
            .animation(Self.motion, value: dots)
            .overlay { interactionLayer }
            .accessibilityElement()
            .accessibilityLabel("\(frets)-fret guitar fretboard")
            .accessibilityValue(FretboardAccessibility.describe(dots: dots, tuning: tuning, fretCount: frets))
    }

    /// One transparent layer over the whole board rather than a gesture per
    /// dot: an empty cell has no view to attach a gesture to, and the Notes
    /// screen needs those most of all.
    @ViewBuilder
    private var interactionLayer: some View {
        if onHit != nil || onLongPress != nil {
            GeometryReader { proxy in
                let geometry = BoardGeometry(
                    size: proxy.size,
                    frets: frets,
                    strings: tuning.openMIDINotes.count,
                    flipped: flipped,
                    margins: margins
                )
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if lastTouch != value.location { longPressFired = false }
                                lastTouch = value.location
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: Self.longPressDuration)
                            .onEnded { _ in
                                guard let hit = hit(at: lastTouch, geometry: geometry) else { return }
                                longPressFired = true
                                onLongPress?(hit)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard !longPressFired else {
                                    longPressFired = false
                                    return
                                }
                                guard let hit = hit(at: value.location, geometry: geometry) else { return }
                                onHit?(hit)
                            }
                    )
            }
        }
    }

    private func hit(at location: CGPoint, geometry: BoardGeometry) -> FretboardHit? {
        FretboardHitTest.resolve(location: location, geometry: geometry, frets: frets, dots: dots)
    }
}

/// Drawn beneath the dots so an annotation frames them rather than covering
/// them.
private struct OverlayLayer: View {
    let overlays: [FretboardOverlay]
    let dots: [FretboardDot]
    let geometry: BoardGeometry

    var body: some View {
        Canvas { context, _ in
            for overlay in overlays {
                let points = overlay.resolve(against: dots).map { geometry.point($0.position) }
                guard !points.isEmpty else { continue }
                switch overlay.kind {
                case .group:
                    context.stroke(
                        Path(roundedRect: boundingBox(of: points).insetBy(dx: -16, dy: -12), cornerRadius: 10),
                        with: .color(overlay.color),
                        lineWidth: 1.5
                    )
                case .sequence:
                    var path = Path()
                    path.addLines(points)
                    context.stroke(path, with: .color(overlay.color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
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

    /// A dot at the default radius uses the exact text style the detection
    /// board's markers have always used, so that board renders pixel for
    /// pixel as it did before it started drawing through here — verified by
    /// snapshot. A resized dot, which only the layered module views ask for,
    /// scales instead; the coefficient is chosen so the two meet at the
    /// default size rather than stepping.
    private var labelFont: Font {
        dot.radius == FretboardDot.defaultRadius
            ? .caption2.weight(.bold)
            : .system(size: dot.radius * 0.645, weight: .bold)
    }

    var body: some View {
        let diameter = dot.radius * 2 * (1 + Self.pulseGrowth * CGFloat(pulse))
        Text(dot.label)
            .font(labelFont)
            .foregroundStyle(dot.labelColor)
            .frame(width: diameter, height: diameter)
            .background(dot.color, in: Circle())
            .overlay {
                if let stroke = dot.stroke {
                    Circle().strokeBorder(stroke, lineWidth: 1)
                }
            }
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
