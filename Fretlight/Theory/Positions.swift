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

    static func compactVoicing(root: PitchClass, intervals: [Int], tuning: Tuning = Tunings.standard, fretCount: Int) -> [NeckPosition] {
        guard let anchor = firstPosition(pitchClass: root, tuning: tuning, fretCount: fretCount) else { return [] }
        var used: Set<Int> = []
        return intervals.compactMap { interval in
            let all = findAll(pitchClasses: [root.transposed(by: interval)], tuning: tuning, fretCount: fretCount)
            var candidates = all.filter { abs($0.midiNote - anchor.midiNote) <= 7 && $0.midiNote >= anchor.midiNote - 2 && !used.contains($0.string) }
            if candidates.isEmpty { candidates = all.filter { !used.contains($0.string) } }
            if candidates.isEmpty { candidates = all }
            // Web ties inherit high-string-first stable-sort order. This app is
            // low-string-first, so an explicit lower-index tie-break is clearer
            // and repeatable even though it may choose the other equal option.
            let chosen = candidates.min {
                let leftDistance = abs($0.midiNote - (anchor.midiNote + interval))
                let rightDistance = abs($1.midiNote - (anchor.midiNote + interval))
                return leftDistance == rightDistance ? $0.string < $1.string : leftDistance < rightDistance
            }
            if let chosen { used.insert(chosen.string) }
            return chosen
        }
    }
}
