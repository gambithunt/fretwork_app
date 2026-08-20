import SwiftUI

struct TunerPanel: View {
    let display: PitchDisplayState

    var body: some View {
        HStack(spacing: 28) {
            noteBlock
            Divider().frame(height: 96)
            VStack(spacing: 9) {
                // The needle is smoothed at the source (AudioAnalysisWorker)
                // and the stream is rate-limited before it gets here
                // (AppState.publish), so it no longer carries a per-update
                // ease. That ease lasted 180ms while updates arrived every
                // 33ms, so it restarted before it could ever finish and
                // pinned the whole window at 60fps — measured at 10 points of
                // a core. TunerGauge stays Animatable: the panel spring below
                // still interpolates the needle when the note changes.
                TunerGauge(displayCents: display.note?.cents ?? 0, isActive: display.note != nil)
                    .frame(height: 54)
                centsReadout
            }
            .frame(maxWidth: .infinity)
            frequencyBlock
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    /// Pitch class as a flat, unadorned color chip beside the letter, and the
    /// octave demoted to a caption underneath — the note's name is the one
    /// thing worth reading across the room, so nothing else competes with it
    /// at that weight.
    private var noteBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(display.note.map { NotePalette.color(for: $0.name) } ?? Color.white.opacity(0.14))
                .frame(width: 16, height: 16)
                .padding(.top, 15)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let note = display.note {
                        Text(note.name)
                            .id(note.midiNote)
                            .transition(.scale(scale: 0.65).combined(with: .opacity))
                    } else {
                        // Dimmed: at this weight and size a full-strength
                        // placeholder shouts as loudly as a real reading.
                        Text("—")
                            .foregroundStyle(.white.opacity(0.22))
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 62, weight: .black)).tracking(-2)
                Text(display.note.map { "OCTAVE \($0.octave)" } ?? "NO SIGNAL")
                    .font(.caption2.weight(.bold)).tracking(1.5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 172, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: display.note?.midiNote)
    }

    // Branching rather than flipping one Text's content between "Listening…"
    // and the cents readout. A plain content mutation under an active
    // animation is what produced the overlapping/garbled text glitch, and
    // while no animation reaches this view any more — the spring is scoped to
    // the note block now — an identity per state is what keeps that true if
    // one ever does.
    private var centsReadout: some View {
        Group {
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
        }
        .frame(height: 24)
    }

    /// Value over unit, same stacking as the note over its octave, so the two
    /// ends of the panel read as one system.
    private var frequencyBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(display.frequency.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 25, weight: .black, design: .monospaced))
                // Inert while no animation reaches this block, and kept for
                // the same reason as the one on the level readout: it is what
                // stops the digits rendering on top of each other if an
                // animation is ever put back in scope.
                .contentTransition(.numericText())
            Text("HERTZ")
                .font(.caption2.weight(.bold)).tracking(1.5)
                .foregroundStyle(.secondary)
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
