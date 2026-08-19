import SwiftUI

struct InputLevelPanel: View {
    let level: Float
    static func decibels(_ level: Float) -> Double { 20 * log10(max(Double(level), 0.000_001)) }
    static func normalized(_ level: Float) -> Double { min(max((decibels(level) + 60) / 60, 0), 1) }

    /// Highest level seen recently, falling back at a fixed rate. Drawn as a
    /// single bright column against the lit field, so a transient that's gone
    /// before the eye catches it still leaves a mark.
    @State private var peak: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("INPUT LEVEL")
                    .font(.caption2.weight(.bold)).tracking(1.6).foregroundStyle(.secondary)
                Spacer(minLength: 24)
                Text(String(format: "%.0f", Self.decibels(level)))
                    .font(.system(size: 19, weight: .black, design: .monospaced))
                    // level changes ~30x/sec while listening, under the
                    // .animation(value: level) below — a plain string swap
                    // has no defined animation, which is what rendered as
                    // overlapping/garbled digits. This gives SwiftUI an
                    // actual digit-rolling transition to run instead.
                    .contentTransition(.numericText())
                Text("DB")
                    .font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
            }
            DotMatrixMeter(level: Self.normalized(level), peak: peak)
        }
        .padding(.horizontal, 22).padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .animation(.easeOut(duration: 0.08), value: level)
        .onChange(of: level) { _, new in
            let now = Self.normalized(new)
            // Jump straight to a new peak, but only ever ease back down —
            // roughly 11 dB per second, the usual broadcast fallback rate.
            peak = now >= peak ? now : max(now, peak - 0.006)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(String(format: "%.0f decibels", Self.decibels(level)))
    }
}

/// A grid of dots rather than a solid bar: columns light left to right with
/// level, and the whole field stays visible when silent, so the meter reads
/// as an instrument face instead of an empty trough.
private struct DotMatrixMeter: View {
    let level: Double
    let peak: Double
    private let pitch: CGFloat = 9
    private let dot: CGFloat = 5
    private let rows = 4

    var body: some View {
        Canvas { context, size in
            // Column count follows the available width instead of being
            // fixed, so the grid stays full-bleed at any window size — the
            // dot pitch is what's constant, not the number of dots.
            let columns = max(2, Int(size.width / pitch))
            let inset = (pitch - dot) / 2
            let originX = (size.width - CGFloat(columns) * pitch) / 2 + inset
            let originY = (size.height - CGFloat(rows) * pitch) / 2 + inset
            let lit = Int((level * Double(columns)).rounded())
            let peakColumn = peak > 0 ? min(columns - 1, Int((peak * Double(columns)).rounded()) - 1) : -1
            for column in 0..<columns {
                let x = originX + CGFloat(column) * pitch
                let color: Color = column == peakColumn
                    ? .white
                    : (column < lit ? Self.zoneColor(Double(column) / Double(columns - 1)) : .white.opacity(0.10))
                for row in 0..<rows {
                    let rect = CGRect(x: x, y: originY + CGFloat(row) * pitch, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .frame(height: CGFloat(rows) * 9)
    }

    // Standard broadcast VU-meter convention — green through most of the
    // range, yellow as it climbs, red only near the very top as a clipping
    // warning — rather than a green/yellow/orange split, which never
    // actually signaled "too hot."
    private static func zoneColor(_ fraction: Double) -> Color {
        fraction < 0.69 ? .green : (fraction < 0.885 ? .yellow : .red)
    }
}
