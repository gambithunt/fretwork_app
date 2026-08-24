import Foundation

struct NeckPosition: Hashable, Sendable {
    let string: Int
    let fret: Int
    let midiNote: Int
    let pitchClass: PitchClass
}

enum Positions: Sendable {
    static func findAll(pitchClasses: [PitchClass], tuning: Tuning = Tunings.standard, fretCount: Int) -> [NeckPosition] {
        let targets = Set(pitchClasses)
        return tuning.openMIDINotes.enumerated().flatMap { string, open in
            (0...fretCount).compactMap { fret in
                let midi = open + fret
                let pitchClass = PitchClass(midi)
                guard targets.contains(pitchClass) else { return nil }
                return NeckPosition(string: string, fret: fret, midiNote: midi, pitchClass: pitchClass)
            }
        }
    }

    /// This app stores the low string at index 0, so walking upward through
    /// indices is the native equivalent of the web app's reverse traversal.
    static func firstPosition(pitchClass: PitchClass, tuning: Tuning = Tunings.standard, fretCount: Int) -> NeckPosition? {
        for string in tuning.openMIDINotes.indices {
            for fret in 0...fretCount {
                let midi = tuning.openMIDINotes[string] + fret
                if PitchClass(midi) == pitchClass {
                    return NeckPosition(string: string, fret: fret, midiNote: midi, pitchClass: pitchClass)
                }
            }
        }
        return nil
    }
}
