import Foundation

/// Pure formatting/derivation helpers for the tuner readouts.
///
/// The views stay thin: they call these rather than embedding `String(format:)`
/// and thresholds, so the rules (what counts as in tune, how a silent note
/// reads) are unit-testable with no view or audio in the process.
enum IOSReadoutFormat {
    /// The "in tune" band, matching the gauge's green zone and the app's own
    /// ±8 cent in-tune judgement — here tightened to ±5 for the compact
    /// landscape pill (D-25).
    static let inTuneCentsThreshold = 5.0

    enum CentsTint: Equatable {
        case inTune
        case offTune
    }

    static func centsTint(_ cents: Double?) -> CentsTint {
        guard let cents else { return .offTune }
        return abs(cents) <= inTuneCentsThreshold ? .inTune : .offTune
    }

    static func centsText(_ cents: Double?) -> String {
        guard let cents else { return "—" }
        return String(format: "%+.0f¢", cents)
    }

    static func noteLabel(_ note: MappedNote?) -> String {
        guard let note else { return "—" }
        return "\(note.name)\(note.octave)"
    }

    static func chordLabel(_ chord: ChordMatch?) -> String {
        guard let chord else { return "—" }
        return chord.name
    }

    static func frequencyText(_ frequency: Double?) -> String {
        frequency.map { String(format: "%.1f", $0) } ?? "—"
    }

    /// The meter's dB figure, with the same noise floor the Mac meter uses.
    static func decibels(_ level: Float) -> Double {
        20 * log10(max(Double(level), 0.000_001))
    }

    static func decibelsText(_ level: Float) -> String {
        String(format: "%.0f", decibels(level))
    }

    /// The same 0...1 normalisation the meter uses.
    static func normalizedLevel(_ level: Float) -> Double {
        min(max((decibels(level) + 60) / 60, 0), 1)
    }

    /// How far the "● Listening" dot swells with a level reading; Reduce Motion
    /// pins it at 1 (no pulse).
    static func pulseScale(normalizedLevel: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1.0 : 1.0 + normalizedLevel * 0.4
    }
}
