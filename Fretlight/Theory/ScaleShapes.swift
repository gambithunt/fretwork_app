import Foundation

enum PentatonicQuality: String, Sendable {
    case minorPentatonic
    case majorPentatonic
}

enum OneOctaveScaleQuality: String, Sendable {
    case major
    case naturalMinor
}

enum FrettingFinger: Int, Sendable {
    case open = 0
    case index = 1
    case middle = 2
    case ring = 3
    case little = 4
}

struct GuidedScaleStep: Sendable {
    let id: String
    let string: Int
    let fret: Int
    let midiNote: Int
    let pitchClass: PitchClass
    let degree: String
    let finger: FrettingFinger
}

private struct PatternNote: Sendable {
    let string: Int
    let offset: Int
    let finger: FrettingFinger
}

private struct PentatonicPattern: Sendable {
    let aMinorBase: Int
    let notes: [PatternNote]
}

enum ScaleShapes: Sendable {
    static let pentatonicFretCount = 15

    /// The web data is high-e-first. These pairs are reversed into this app's
    /// Low-E-first order before they can ever be assigned a MIDI note.
    private static let pentatonicPatterns = [
        PentatonicPattern(aMinorBase: 5, notes: pairs([[(0, 1), (3, 4)], [(0, 1), (2, 3)], [(0, 1), (2, 3)], [(0, 1), (2, 3)], [(0, 1), (3, 4)], [(0, 1), (3, 4)]])),
        PentatonicPattern(aMinorBase: 7, notes: pairs([[(1, 2), (3, 4)], [(0, 1), (3, 4)], [(0, 1), (3, 4)], [(0, 1), (2, 3)], [(1, 2), (3, 4)], [(1, 2), (3, 4)]])),
        PentatonicPattern(aMinorBase: 9, notes: pairs([[(1, 1), (3, 3)], [(1, 1), (3, 3)], [(1, 1), (3, 3)], [(0, 1), (3, 4)], [(1, 1), (4, 4)], [(1, 1), (3, 3)]])),
        PentatonicPattern(aMinorBase: 12, notes: pairs([[(0, 1), (3, 4)], [(0, 1), (3, 4)], [(0, 1), (2, 3)], [(0, 1), (2, 3)], [(1, 2), (3, 4)], [(0, 1), (3, 4)]])),
        PentatonicPattern(aMinorBase: 2, notes: pairs([[(1, 2), (3, 4)], [(1, 2), (3, 4)], [(0, 1), (3, 4)], [(0, 1), (3, 4)], [(1, 2), (3, 4)], [(1, 2), (3, 4)]]))
    ]

    /// Standard tuning only, and deliberately not parameterised by one. These
    /// boxes are fixed fret offsets from a computed base, so a different
    /// tuning does not transpose them — it detunes them, and the box quietly
    /// stops being the scale it claims to be. `oneOctaveScale` derives every
    /// note from MIDI instead, which is why that one does take a tuning.
    static func pentatonicPosition(root: PitchClass, quality: PentatonicQuality, position: Int) -> [GuidedScaleStep] {
        let tuning = Tunings.standard
        guard pentatonicPatterns.indices.contains(position), let scale = Scales.scale(id: quality.rawValue) else { return [] }
        let pattern = pentatonicPatterns[position]
        let relativeMinor = quality == .minorPentatonic ? root : root.transposed(by: 9)
        let transposition = (relativeMinor.value - 9 + 12) % 12
        let maximumOffset = pattern.notes.map(\.offset).max() ?? 0
        let base = fitWholePattern(pattern.aMinorBase + transposition, maximumOffset: maximumOffset)

        return pattern.notes.enumerated().map { index, note in
            let fret = base + note.offset
            let midi = tuning.openMIDINotes[note.string] + fret
            let pitchClass = PitchClass(midi)
            let degree = scale.intervals.enumerated().first { root.transposed(by: $0.element) == pitchClass }
                .map { scale.degrees[$0.offset] } ?? ""
            return GuidedScaleStep(id: "pent-\(position)-\(note.string)-\(index % 2)", string: note.string, fret: fret, midiNote: midi, pitchClass: pitchClass, degree: degree, finger: fret == 0 ? .open : note.finger)
        }.sorted { $0.midiNote < $1.midiNote }
    }

    static func oneOctaveScale(root: PitchClass, quality: OneOctaveScaleQuality, tuning: Tuning = Tunings.standard) -> [GuidedScaleStep] {
        guard let scale = Scales.scale(id: quality.rawValue) else { return [] }
        let lowEFret = (root.value - PitchClass(tuning.openMIDINotes[0]).value + 12) % 12
        let aFret = (root.value - PitchClass(tuning.openMIDINotes[1]).value + 12) % 12
        // The web chooses A then low E while walking toward its smaller index;
        // this app chooses 1 then 0 and advances toward larger indices.
        var string = aFret <= lowEFret ? 1 : 0
        let anchorFret = string == 1 ? aFret : lowEFret
        let baseMIDI = tuning.openMIDINotes[string] + anchorFret
        let intervals = scale.intervals + [12]
        let degrees = scale.degrees + ["1"]
        var raw: [(index: Int, string: Int, fret: Int, midi: Int, degree: String)] = []
        var notesOnString = 0
        for (index, interval) in intervals.enumerated() {
            let midi = baseMIDI + interval
            var fret = midi - tuning.openMIDINotes[string]
            if (notesOnString >= 3 || fret > anchorFret + 4), string < tuning.openMIDINotes.count - 1 {
                string += 1
                notesOnString = 0
                fret = midi - tuning.openMIDINotes[string]
            }
            raw.append((index, string, fret, midi, degrees[index]))
            notesOnString += 1
        }
        return raw.map { note in
            let frets = raw.filter { $0.string == note.string }.map(\.fret)
            let order = raw.filter { $0.string == note.string }.firstIndex { $0.index == note.index } ?? 0
            return GuidedScaleStep(id: "scale-\(note.index)", string: note.string, fret: note.fret, midiNote: note.midi, pitchClass: PitchClass(note.midi), degree: note.degree, finger: fingers(for: frets)[order])
        }
    }

    static func buildScaleSequence(_ steps: [GuidedScaleStep], upDown: Bool) -> [GuidedScaleStep] {
        let ascending = steps.sorted { $0.midiNote < $1.midiNote }
        guard upDown, ascending.count > 1 else { return ascending }
        return ascending + ascending.dropLast().reversed()
    }

    /// MIDI ordering is deliberately retained from the web implementation:
    /// route direction concerns physical travel, not which string is numbered first.
    static func pentatonicRoute(root: PitchClass, quality: PentatonicQuality, positions: [Int]) -> [GuidedScaleStep] {
        positions.enumerated().flatMap { index, position in
            let steps = pentatonicPosition(root: root, quality: quality, position: position)
            return index.isMultiple(of: 2) ? steps.sorted { $0.midiNote > $1.midiNote } : steps
        }
    }

    private static func pairs(_ values: [[(Int, Int)]]) -> [PatternNote] {
        values.enumerated().flatMap { string, pair in
            pair.map { PatternNote(string: string, offset: $0.0, finger: FrettingFinger(rawValue: $0.1) ?? .index) }
        }
    }

    private static func fitWholePattern(_ base: Int, maximumOffset: Int) -> Int {
        var fitted = (base % 12 + 12) % 12
        while fitted + maximumOffset > pentatonicFretCount { fitted -= 12 }
        if fitted < 0 { fitted += 12 }
        return fitted
    }

    private static func fingers(for frets: [Int]) -> [FrettingFinger] {
        guard let first = frets.first, let last = frets.last else { return [] }
        return frets.enumerated().map { index, fret in
            if fret == 0 { return .open }
            if first == 0 { return FrettingFinger(rawValue: min(fret, 4)) ?? .little }
            if frets.count == 1 { return .index }
            if index == 0 { return .index }
            if index == frets.count - 1 { return FrettingFinger(rawValue: min(4, max(2, last - first + 1))) ?? .little }
            return fret - first > last - fret ? .ring : .middle
        }
    }
}
