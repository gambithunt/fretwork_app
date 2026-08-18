import SwiftUI

struct LevelMeterView: View {
    let level: Float
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
            ProgressView(value: min(Double(level) * 4, 1)).tint(level > 0.18 ? .orange : .green).frame(width: 180)
            Text(String(format: "%.0f dB", 20 * log10(max(Double(level), 0.000_001)))).monospacedDigit()
        }
    }
}
