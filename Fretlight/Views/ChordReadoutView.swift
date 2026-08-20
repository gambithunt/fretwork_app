import SwiftUI

/// Mirrors TunerPanel's card shell, but a chord name is a whole different
/// word each time it changes ("D" to "Am7"), not a value that eases from one
/// number to another — so this branches by identity per state, same as
/// TunerPanel.centsReadout, rather than reaching for .contentTransition
/// (built for in-place digit/symbol changes, and it's why that panel had to
/// stop doing this the naive way).
struct ChordPanel: View {
    let chord: ChordDisplayState

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let match = chord.chord {
                    Text(match.name)
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .id(match.name)
                        .transition(.opacity)
                } else {
                    Text("Strum a chord")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: chord.chord?.name)
            Text(chord.chord.map { String(format: "%.0f%% match", $0.confidence * 100) } ?? " ")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}
