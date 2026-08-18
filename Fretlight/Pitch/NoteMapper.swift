import Foundation

struct FretPosition: Hashable, Sendable { let string: Int; let fret: Int }

struct MappedNote: Sendable {
    let name: String
    let octave: Int
    let midiNote: Int
    let cents: Double
    let positions: Set<FretPosition>
}

enum NoteMapper {
    static func map(frequency: Double, fretCount: Int = 22) -> MappedNote? {
        guard frequency.isFinite, frequency > 0 else { return nil }
        let exactMIDI = 69 + 12 * log2(frequency / 440)
        let midi = Int(exactMIDI.rounded())
        let cents = (exactMIDI - Double(midi)) * 100
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        var positions = Set<FretPosition>()
        for (string, open) in GuitarTuning.openMIDINotes.enumerated() {
            let fret = midi - open
            if (0...fretCount).contains(fret) { positions.insert(FretPosition(string: string, fret: fret)) }
        }
        return MappedNote(name: names[(midi % 12 + 12) % 12], octave: midi / 12 - 1, midiNote: midi, cents: cents, positions: positions)
    }
}
