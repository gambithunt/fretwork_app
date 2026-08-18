import SwiftUI

struct TunerPanel: View {
    let display: PitchDisplayState
    var body: some View {
        HStack(spacing: 28) {
            Group {
                if let note = display.note {
                    Text("\(note.name)\(note.octave)")
                        .id(note.midiNote)
                        .transition(.scale(scale: 0.65).combined(with: .opacity))
                } else {
                    Text("—")
                        .transition(.opacity)
                }
            }
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .frame(width: 145, alignment: .leading)
            Divider().frame(height: 96)
            VStack(spacing: 9) {
                TunerGauge(cents: display.note?.cents).frame(height: 54)
                // A single Text whose *content* flips between "Listening…"
                // and the cents readout — under the shared spring animation
                // below — is exactly what produced the overlapping/garbled
                // text glitch: SwiftUI has no transition to animate a plain
                // content mutation, so old and new could render mid-swap.
                // Branching gives each state its own identity and an
                // explicit crossfade, same as the note text above.
                Group {
                    if let note = display.note {
                        Text(String(format: "%+.1f cents", note.cents))
                            .foregroundStyle(abs(note.cents) < 8 ? Color.green : Color.orange)
                            .transition(.opacity)
                    } else {
                        Text("Listening…")
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .font(.title3.monospacedDigit().weight(.medium))
            }
            .frame(maxWidth: .infinity)
            Text(display.frequency.map { String(format: "%.2f Hz", $0) } ?? "— Hz")
                .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: display.note?.midiNote)
    }
}

struct TunerGauge: View {
    let cents: Double?
    var body: some View {
        Canvas { context, size in
            let y = size.height * 0.62
            let left = size.width * 0.04
            let right = size.width * 0.96
            var baseline = Path(); baseline.move(to: CGPoint(x: left, y: y)); baseline.addLine(to: CGPoint(x: right, y: y))
            context.stroke(baseline, with: .color(.white.opacity(0.22)), lineWidth: 2)
            for tick in 0...20 {
                let x = left + (right - left) * CGFloat(tick) / 20
                let major = tick.isMultiple(of: 5)
                var mark = Path(); mark.move(to: CGPoint(x: x, y: y - (major ? 16 : 8))); mark.addLine(to: CGPoint(x: x, y: y + 5))
                context.stroke(mark, with: .color(.white.opacity(major ? 0.6 : 0.35)), lineWidth: 1)
                if major {
                    let value = -50 + tick * 5
                    context.draw(Text("\(value > 0 ? "+" : "")\(value)").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: x, y: 8))
                }
            }
            let value = max(-50, min(50, cents ?? 0))
            let x = left + (right - left) * CGFloat((value + 50) / 100)
            var needle = Path(); needle.move(to: CGPoint(x: x, y: y - 22)); needle.addLine(to: CGPoint(x: x, y: y + 14))
            let needleColor: Color = cents == nil ? .secondary : (abs(cents!) < 8 ? .green : .orange)
            context.stroke(needle, with: .color(needleColor), lineWidth: 2)
        }
    }
}
