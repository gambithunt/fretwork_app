import SwiftUI

/// One card shell shared by Notes and Chords — switching modes swaps what's
/// *inside* each of the three blocks (headline, gauge/status, secondary
/// reading) rather than swapping in a whole different panel. A whole-panel
/// swap collapses the layout to whatever the new panel's natural size is,
/// which reads as the UI jumping; keeping one shape and re-labelling it
/// reads as the same instrument switching what it's listening for.
struct TunerPanel: View {
    let mode: DetectionMode
    let display: PitchDisplayState
    let chord: ChordDisplayState

    var body: some View {
        HStack(spacing: 28) {
            headlineBlock
            Divider().frame(height: 96)
            VStack(spacing: 9) {
                switch mode {
                case .notes:
                    TunerGauge(displayCents: display.note?.cents ?? 0, isActive: display.note != nil)
                        .frame(height: 54)
                case .chords:
                    // The gauge is a cents needle — meaningless for a chord,
                    // there's no one pitch to point at — so this doesn't
                    // reuse it dimmed-and-idle. What actually belongs at
                    // center stage in Chords mode is the chord itself: the
                    // one thing this whole mode exists to tell you, given
                    // the room the note-mode needle otherwise leaves empty.
                    chordNameReadout
                }
                statusReadout
            }
            .frame(maxWidth: .infinity)
            secondaryBlock
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
        .glassCard()
    }

    /// What identifies "the current reading" for the spring below — a new
    /// note's MIDI number in Notes mode, a new chord's name in Chords mode.
    private var headlineKey: String? {
        switch mode {
        case .notes: return display.note.map { String($0.midiNote) }
        case .chords: return chord.chord?.root
        }
    }

    /// Pitch class (or chord root) as a flat, unadorned color chip beside the
    /// letter, and the octave/qualifier demoted to a caption underneath —
    /// the name is the one thing worth reading across the room, so nothing
    /// else competes with it at that weight. In Chords mode this shows the
    /// root alone, not the full chord name — the name itself now has its
    /// own centered spot (`chordNameReadout`) where the note-mode gauge
    /// used to be, so this block stays what it's always been: an at-a-glance
    /// pitch-class chip, not a second copy of the headline reading.
    private var headlineBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(headlineColor)
                .frame(width: 16, height: 16)
                .padding(.top, 15)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    switch mode {
                    case .notes:
                        if let note = display.note {
                            Text(note.name)
                                .id(note.midiNote)
                                .transition(.scale(scale: 0.65).combined(with: .opacity))
                        } else {
                            placeholderGlyph
                        }
                    case .chords:
                        if let match = chord.chord {
                            Text(match.root)
                                .id(match.root)
                                .transition(.scale(scale: 0.65).combined(with: .opacity))
                        } else {
                            placeholderGlyph
                        }
                    }
                }
                .font(.system(size: 62, weight: .black)).tracking(-2)
                Text(subtitle)
                    .font(.caption2.weight(.bold)).tracking(1.5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 172, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: headlineKey)
    }

    /// Centered where the cents gauge sits in Notes mode — the chord name is
    /// the one thing this whole mode exists to report, so it gets the same
    /// stage the needle gets, not a corner of it.
    private var chordNameReadout: some View {
        Group {
            if let match = chord.chord {
                Text(match.name)
                    .id(match.name)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                Text("—")
                    .foregroundStyle(.white.opacity(0.22))
                    .transition(.opacity)
            }
        }
        .font(.system(size: 40, weight: .black, design: .rounded))
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: chord.chord?.name)
    }

    // Dimmed: at this weight and size a full-strength placeholder shouts as
    // loudly as a real reading.
    private var placeholderGlyph: some View {
        Text("—")
            .foregroundStyle(.white.opacity(0.22))
            .transition(.opacity)
    }

    private var headlineColor: Color {
        switch mode {
        case .notes: return display.note.map { NotePalette.color(for: $0.name) } ?? Color.white.opacity(0.14)
        case .chords: return chord.chord.map { NotePalette.color(for: $0.root) } ?? Color.white.opacity(0.14)
        }
    }

    private var subtitle: String {
        switch mode {
        case .notes: return display.note.map { "OCTAVE \($0.octave)" } ?? "NO SIGNAL"
        case .chords: return chord.chord != nil ? "ROOT" : "NO SIGNAL"
        }
    }

    // Branching rather than flipping one Text's content between states — a
    // plain content mutation under an active animation is what produced the
    // overlapping/garbled text glitch this codebase hit before, and an
    // identity per state is what keeps that true.
    private var statusReadout: some View {
        Group {
            switch mode {
            case .notes:
                if let note = display.note {
                    let inTune = abs(note.cents) < 8
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: inTune ? "checkmark.circle.fill" : (note.cents > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"))
                            .contentTransition(.symbolEffect(.replace))
                        Text(String(format: "%+.1f", note.cents))
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .contentTransition(.numericText())
                        Text("CENTS")
                            .font(.caption2.weight(.bold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(inTune ? Color.green : Color.orange)
                    .transition(.opacity)
                } else {
                    Text("LISTENING")
                        .font(.caption2.weight(.bold)).tracking(1.6)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            case .chords:
                Text(chord.chord != nil ? "CHORD DETECTED" : "LISTENING")
                    .font(.caption2.weight(.bold)).tracking(1.6)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(height: 24)
    }

    /// Value over unit, same stacking as the headline over its qualifier, so
    /// the two ends of the panel read as one system: Hertz for a note's
    /// exact pitch, template-match confidence for a chord's.
    private var secondaryBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch mode {
            case .notes:
                Text(display.frequency.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 25, weight: .black, design: .monospaced))
                    // Inert while no animation reaches this block, and kept
                    // for the same reason as the one on the level readout:
                    // it is what stops the digits rendering on top of each
                    // other if an animation is ever put back in scope.
                    .contentTransition(.numericText())
                Text("HERTZ")
                    .font(.caption2.weight(.bold)).tracking(1.5)
                    .foregroundStyle(.secondary)
            case .chords:
                Text(chord.chord.map { String(format: "%.0f", $0.confidence * 100) } ?? "—")
                    .font(.system(size: 25, weight: .black, design: .monospaced))
                    .contentTransition(.numericText())
                Text("MATCH")
                    .font(.caption2.weight(.bold)).tracking(1.5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 132, alignment: .trailing)
    }
}

struct TunerGauge: View, Animatable {
    /// Non-optional and always in range, so this can be SwiftUI's
    /// `animatableData` — `Double?` doesn't conform to `VectorArithmetic`,
    /// so an Optional can't be interpolated directly. `isActive` (not part
    /// of animatableData; a plain discrete toggle) carries whether there's
    /// actually a note to report, for the needle's color/visibility.
    var displayCents: Double
    var isActive: Bool

    // Animatable's requirement isn't itself @MainActor-isolated, but View's
    // is, so conforming to both under strict concurrency needs an explicit
    // nonisolated here — this is pure value access, nothing UI-touching.
    nonisolated var animatableData: Double {
        get { displayCents }
        set { displayCents = newValue }
    }

    /// Traffic-light zones: green at the center — the same ±8 cent "in
    /// tune" threshold used everywhere else this app judges tuning — fading
    /// through yellow to red at the ±50 extremes.
    private static let zoneGradient = Gradient(stops: [
        .init(color: .red, location: 0.0),
        .init(color: .yellow, location: 0.25),
        .init(color: .green, location: 0.42),
        .init(color: .green, location: 0.58),
        .init(color: .yellow, location: 0.75),
        .init(color: .red, location: 1.0),
    ])

    /// Discrete version of the same zones, for the needle and individual
    /// tick marks — Canvas gradients shade smoothly along a path, but
    /// there's no public API to sample a Gradient at an arbitrary point,
    /// so single-color elements use this instead.
    private static func zoneColor(forCents cents: Double) -> Color {
        let magnitude = abs(cents)
        if magnitude < 8 { return .green }
        if magnitude < 25 { return .yellow }
        return .red
    }

    var body: some View {
        Canvas { context, size in
            let y = size.height * 0.62
            let left = size.width * 0.04
            let right = size.width * 0.96
            var baseline = Path(); baseline.move(to: CGPoint(x: left, y: y)); baseline.addLine(to: CGPoint(x: right, y: y))
            context.stroke(baseline, with: .linearGradient(Self.zoneGradient, startPoint: CGPoint(x: left, y: y), endPoint: CGPoint(x: right, y: y)), lineWidth: 2)
            for tick in 0...20 {
                let x = left + (right - left) * CGFloat(tick) / 20
                let major = tick.isMultiple(of: 5)
                let value = -50 + tick * 5
                var mark = Path(); mark.move(to: CGPoint(x: x, y: y - (major ? 16 : 8))); mark.addLine(to: CGPoint(x: x, y: y + 5))
                context.stroke(mark, with: .color(Self.zoneColor(forCents: Double(value)).opacity(major ? 0.85 : 0.5)), lineWidth: 1)
                if major {
                    context.draw(Text("\(value > 0 ? "+" : "")\(value)").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: x, y: 8))
                }
            }
            let value = max(-50, min(50, displayCents))
            let x = left + (right - left) * CGFloat((value + 50) / 100)
            var needle = Path(); needle.move(to: CGPoint(x: x, y: y - 22)); needle.addLine(to: CGPoint(x: x, y: y + 14))
            let needleColor: Color = isActive ? Self.zoneColor(forCents: displayCents) : .secondary
            context.stroke(needle, with: .color(needleColor), lineWidth: 2.5)
        }
    }
}
