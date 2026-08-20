import SwiftUI

/// A ruler-and-knob dial in place of a plain track: the value reads as a
/// number on the knob instead of having to be inferred from a thumb's
/// position, and the ticks give the travel a sense of scale. Same 0...1
/// binding a `Slider` took — the 0–10 the knob prints is presentation only.
struct RulerSlider: View {
    @Binding var value: Double
    var isEnabled: Bool = true

    private let knob: CGFloat = 21
    private let tickSpacing: CGFloat = 6
    private let steps = 10
    @FocusState private var focused: Bool

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width - knob
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let count = max(2, Int((size.width - knob) / tickSpacing))
                    for tick in 0...count {
                        let fraction = Double(tick) / Double(count)
                        let x = knob / 2 + (size.width - knob) * fraction
                        let major = tick.isMultiple(of: 5)
                        let height: CGFloat = major ? 13 : 8
                        // Ticks the knob has already passed sit brighter, so
                        // the dial still shows its level at a glance without
                        // a filled track competing with the knob.
                        let passed = fraction <= clamped
                        var mark = Path()
                        mark.move(to: CGPoint(x: x, y: size.height / 2 - height / 2))
                        mark.addLine(to: CGPoint(x: x, y: size.height / 2 + height / 2))
                        context.stroke(
                            mark,
                            with: .color(.white.opacity(isEnabled ? (passed ? 0.5 : 0.2) : 0.12)),
                            lineWidth: 1
                        )
                    }
                }
                Text("\(Int((clamped * Double(steps)).rounded()))")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(isEnabled ? .black : .black.opacity(0.45))
                    .frame(width: knob, height: knob)
                    .background(Color.white.opacity(isEnabled ? 1 : 0.3), in: Circle())
                    .overlay(Circle().strokeBorder(.tint, lineWidth: focused ? 2 : 0))
                    .position(x: knob / 2 + travel * clamped, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled, travel > 0 else { return }
                        focused = true
                        value = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                    }
            )
        }
        .frame(height: 32)
        .focusable(isEnabled)
        // The knob already draws its own focus ring (the strokeBorder
        // above) — without this, macOS also draws its default rounded-rect
        // focus indicator around the whole control, so a focused slider
        // showed two rings at once.
        .focusEffectDisabled()
        .focused($focused)
        // A native Slider takes arrow keys once focused; a custom control has
        // to say so itself, and one step here is one printed digit.
        .onKeyPress(.leftArrow) { nudge(-1) }
        .onKeyPress(.rightArrow) { nudge(1) }
        .accessibilityElement()
        .accessibilityValue("\(Int((clamped * Double(steps)).rounded())) of \(steps)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = nudge(1)
            case .decrement: _ = nudge(-1)
            @unknown default: break
            }
        }
    }

    private func nudge(_ direction: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        value = min(max(value + direction / Double(steps), 0), 1)
        return .handled
    }
}
