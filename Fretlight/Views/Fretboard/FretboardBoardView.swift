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

    /// Not `FretworkMotion.gravity`, and deliberately **critically damped**:
    /// `bounce: 0` is the whole point of this constant, not a detail of it.
    ///
    /// A dot growing in place has nowhere to travel, so any overshoot is the
    /// dot changing size after it has already arrived — which reads as a
    /// wobble, not as weight. This was `spring(duration: 0.85, bounce: 0.32)`,
    /// and the numbers say why that looked wrong: evaluating `Spring` directly
    /// (see the harness in the session that produced this comment) it
    /// overshoots to 1.022× full size, crosses full size three times, and
    /// reports a `settlingDuration` of **1.73s** — the dot is still moving a
    /// second and a half after the note was placed. Worse, `FretboardDotView`
    /// runs its own `pulse` spring over the same 320ms, so a freshly placed
    /// note got two overlapping size animations, one of them ringing.
    ///
    /// At `duration: 0.3, bounce: 0` the same 0.6 → 1 rise is monotonic: 74%
    /// of the way at 60ms, 96% at 180ms, settled at 0.5s, and it never once
    /// passes its target. `duration` sets the spring's characteristic
    /// timescale directly, so this is still slow enough that the growth is
    /// something the eye can follow rather than the 2–3 frame pop `.bouncy`
    /// produced.
    private static let motion = Animation.spring(duration: 0.3, bounce: 0)

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
                    ZStack {
                        OverlayLayer(overlays: overlays, dots: dots, geometry: geometry)
                        ForEach(dots) { dot in
                            let point = geometry.point(dot.position)
                            // Scale and opacity only now — no positional
                            // slide. A dot materialises in place and bounces
                            // to size, the way a Liquid Glass surface blooms
                            // in rather than arrives from a direction. With
                            // dozens of dots capable of appearing at once
                            // (Notes' board routinely holds 50+), several of
                            // them sliding in from different directions
                            // simultaneously was adding visual noise on top
                            // of what was mostly a rendering-cost problem
                            // (see `.drawingGroup()` below).
                            FretboardDotView(dot: dot, pulse: pulses[dot.id] ?? 0)
                                // Positioned by the transition's identity
                                // state, not by a separate `.position` on top
                                // of it — applying both places the dot twice
                                // and it lands somewhere neither modifier
                                // asked for.
                                .transition(
                                    .modifier(
                                        active: DotMotionModifier(x: point.x, y: point.y, scale: 0.6, opacity: 0),
                                        identity: DotMotionModifier(x: point.x, y: point.y, scale: 1, opacity: 1)
                                    )
                                )
                        }
                    }
                    // Every dot draws its own `.shadow()`, and a shadow is a
                    // real per-layer rasterisation cost — with dozens on
                    // screen at once, animating any of them meant Core
                    // Animation re-rasterising dozens of independent blurred
                    // layers every frame, which is what actually produced
                    // the stutter no amount of spring-curve tuning could
                    // fix. `.drawingGroup()` flattens this whole layer to
                    // one Metal-composited texture, so the GPU redraws it as
                    // a single unit instead.
                    .drawingGroup()
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
                                // A gesture's `onEnded` closure runs with no
                                // animation transaction active, unlike a
                                // Button action — the ambient
                                // `.animation(Self.motion, value: dots)` below
                                // does not reliably pick up a change made
                                // from here. Measured directly: without this,
                                // a tapped-in dot popped straight to full size
                                // with no grow at all, while the exact same
                                // mutation wrapped in `withAnimation` (as the
                                // chip pickers already do) grew smoothly. Both
                                // callbacks need the same explicit wrap.
                                withAnimation(Self.motion) { onLongPress?(hit) }
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
                                withAnimation(Self.motion) { onHit?(hit) }
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
            .background(glassFill)
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
            // A soft glow instead of the old hard white edge — the dot's own
            // colour bleeding a few points into the neck around it is what
            // makes it read as lit rather than as a flat sticker. A fixed
            // radius rather than one keyed to `pulse`: animating a shadow's
            // radius every frame is real rendering cost, and it bought
            // nothing here since the dot's own swelling diameter already
            // carries the pulse.
            .shadow(color: dot.color.opacity(0.55 * dot.alpha), radius: 6)
            .opacity(dot.alpha)
            // Everything above this line reacts to `pulse`, which used to
            // change with no animation in scope — a played note's dot would
            // pop to its grown size and pop back rather than swell and
            // settle. Critically damped (`dampingFraction: 1`), not merely
            // close to it: at 0.85 this overshot the swell four times over
            // a 0.72s settle, and a tap that *places* a note runs this on
            // top of the board's arrival spring, so two rings compounded
            // into the shake. A breath in and out has no reason to ring at
            // all. `response` is shortened to 0.34 to keep the swell
            // reaching 97% of full size inside the 320ms the pulse is held
            // for, which critical damping would otherwise stretch past.
            .animation(.spring(response: 0.34, dampingFraction: 1), value: pulse)
    }

    /// Flat and translucent — a single, uniform fill with no radial shading
    /// and no glint standing in for a light source. A gradient plus a
    /// top-left highlight is a specular effect (the same thing the chip
    /// fill's beveled look turned out to be), and the opposite of what
    /// should read as a light marker resting on the neck: something you can
    /// still faintly see the fret grid through, not a lit glass bead.
    private var glassFill: some View {
        Circle().fill(dot.color.opacity(0.82))
    }
}
