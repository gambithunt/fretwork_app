import Foundation

struct MappedNote: Sendable {
    let name: String
    let octave: Int
    let midiNote: Int
    let cents: Double
}

enum NoteMapper {
    /// Shared with `ChordDetector`/`ChordShapeResolver`, which both need to
    /// go between a pitch class name and its index — kept in one place so
    /// the three don't drift out of sync with their own copies.
    static let pitchClassNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// Resolves a frequency to a pitch only. Where that pitch sits on the
    /// fretboard depends on the tuning and on where the hand already is —
    /// neither of which the analysis thread knows — so that mapping happens
    /// later, on the main actor, via `FretPositionResolver`.
    static func map(frequency: Double) -> MappedNote? {
        guard frequency.isFinite, frequency > 0 else { return nil }
        let exactMIDI = 69 + 12 * log2(frequency / 440)
        let midi = Int(exactMIDI.rounded())
        let cents = (exactMIDI - Double(midi)) * 100
        return MappedNote(name: pitchClassNames[(midi % 12 + 12) % 12], octave: midi / 12 - 1, midiNote: midi, cents: cents)
    }
}
