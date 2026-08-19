import SwiftUI

struct TunerPanel: View {
    let display: PitchDisplayState

    var body: some View {
        HStack(spacing: 28) {
            noteBlock
            Divider().frame(height: 96)
            VStack(spacing: 9) {
                // Even with the underlying cents value itself smoothed
                // (AudioAnalysisWorker), each ~33ms update is still a
                // discrete jump — TunerGauge being Animatable lets SwiftUI
                // interpolate the drawn needle position between updates
                // instead of snapping, which is most of what made this
                // read as twitchy rather than a settling needle.
                TunerGauge(displayCents: display.note?.cents ?? 0, isActive: display.note != nil)
                    .frame(height: 54)
                    .animation(.easeOut(duration: 0.18), value: display.note?.cents)
                centsReadout
            }
            .frame(maxWidth: .infinity)
            frequencyBlock
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: display.note?.midiNote)
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
    }

    // A single Text whose *content* flips between "Listening…" and the cents
    // readout — under the shared spring animation above — is exactly what
    // produced the overlapping/garbled text glitch: SwiftUI has no transition
    // to animate a plain content mutation, so old and new could render
    // mid-swap. Branching gives each state its own identity and an explicit
    // crossfade, same as the note text above.
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
                // The panel-wide spring above fires whenever the note
                // changes, and the frequency changes on that same update —
                // without a content transition that's the same garbled
                // in-place mutation the readouts above had to fix.
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
