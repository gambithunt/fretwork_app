import SwiftUI

struct InputLevelPanel: View {
    let level: Float
    static func decibels(_ level: Float) -> Double { 20 * log10(max(Double(level), 0.000_001)) }

    var body: some View {
        let normalized = min(max((Self.decibels(level) + 60) / 60, 0), 1)
        VStack(spacing: 8) {
            Text("INPUT LEVEL").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<52, id: \.self) { index in
                    let threshold = Double(index + 1) / 52
                    Capsule().fill(threshold <= normalized ? meterColor(index) : Color.white.opacity(0.12))
                        .frame(width: 7, height: 18)
                }
                Text(String(format: "%.0f dB", Self.decibels(level)))
                    .font(.body.monospacedDigit()).frame(width: 68, alignment: .trailing)
                    // level changes ~30x/sec while listening, under the
                    // .animation(value: level) below — a plain string swap
                    // has no defined animation, which is what rendered as
                    // overlapping/garbled digits. This gives SwiftUI an
                    // actual digit-rolling transition to run instead.
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 13)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func meterColor(_ index: Int) -> Color { index < 34 ? .green : (index < 44 ? .yellow : .orange) }
}
