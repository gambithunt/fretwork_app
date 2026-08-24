import Foundation

enum HarmonyMode: Sendable {
    case triads
    case doubleStops
}

struct DoubleStop: Sendable {
    let id: String
    let label: String
    let intervals: [Int]
    let degrees: [String]
    let description: String
}

struct VoicingPosition: Sendable {
    let string: Int
    let fret: Int
    let midiNote: Int
    let pitchClass: PitchClass
}

struct VoicingTone: Sendable {
    let interval: Int
    let degree: String
    let position: VoicingPosition
}

struct CompactVoicing: Sendable {
    let id: String
    let tones: [VoicingTone]
    let minFret: Int
    let maxFret: Int
    let stringSet: String
    let inversion: String
}

enum DoubleStops: Sendable {
    static let all = [
        DoubleStop(id: "maj3", label: "Major 3rds", intervals: [0, 4], degrees: ["1", "3"], description: "Bright two-note harmony for major-key lines."),
        DoubleStop(id: "min3", label: "Minor 3rds", intervals: [0, 3], degrees: ["1", "b3"], description: "Darker two-note harmony for minor and blues phrases."),
        DoubleStop(id: "maj6", label: "Major 6ths", intervals: [0, 9], degrees: ["1", "6"], description: "Open, warm harmonised melody shapes."),
        DoubleStop(id: "min6", label: "Minor 6ths", intervals: [0, 8], degrees: ["1", "b6"], description: "A more dramatic, minor-colour double stop."),
        DoubleStop(id: "p4", label: "4ths", intervals: [0, 5], degrees: ["1", "4"], description: "Neutral, suspended-sounding shapes for riffs."),
        DoubleStop(id: "p5", label: "5ths", intervals: [0, 7], degrees: ["1", "5"], description: "The compact two-note version of a power chord.")
    ]
}

enum TriadVoicings: Sendable {
    static let fretCount = 22
    private static let triadStringSets = [[0, 1, 2], [1, 2, 3], [2, 3, 4], [3, 4, 5]]
    private static let doubleStopStringSets = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]]

    static func voicings(root: PitchClass, triad: ChordDef, fretCount: Int = fretCount) -> [CompactVoicing] {
        build(root: root, intervals: triad.intervals, degrees: triad.degrees, stringSets: triadStringSets, kind: .triads, fretCount: fretCount)
    }

    static func doubleStopVoicings(root: PitchClass, definition: DoubleStop, fretCount: Int = fretCount) -> [CompactVoicing] {
        build(root: root, intervals: definition.intervals, degrees: definition.degrees, stringSets: doubleStopStringSets, kind: .doubleStops, fretCount: fretCount)
    }

    private static func build(root: PitchClass, intervals: [Int], degrees: [String], stringSets: [[Int]], kind: HarmonyMode, fretCount: Int) -> [CompactVoicing] {
        var results: [String: CompactVoicing] = [:]
        for strings in stringSets {
            for assignment in permutations(intervals) {
                let choices = assignment.enumerated().map { index, interval in
                    frets(for: strings[index], pitchClass: root.transposed(by: interval), fretCount: fretCount)
                }
                for frets in cartesian(choices) {
                    guard let minFret = frets.min(), let maxFret = frets.max(), maxFret - minFret <= 4 else { continue }
                    let tones = assignment.enumerated().map { index, interval in
                        let midi = Tunings.standard.openMIDINotes[strings[index]] + frets[index]
                        return VoicingTone(
                            interval: interval,
                            degree: degrees[intervals.firstIndex(of: interval) ?? 0],
                            position: VoicingPosition(string: strings[index], fret: frets[index], midiNote: midi, pitchClass: PitchClass(midi))
                        )
                    }
                    let key = "\(strings.map(String.init).joined()):\(frets.map(String.init).joined(separator: ","))"
                    let lowest = tones.min { $0.position.midiNote < $1.position.midiNote }
                    let inversion: String
                    switch kind {
                    case .triads:
                        inversion = lowest?.interval == 0 ? "Root position" : lowest?.interval == intervals[1] ? "1st inversion" : "2nd inversion"
                    case .doubleStops:
                        inversion = lowest?.degree == "1" ? "Root below" : "Colour below"
                    }
                    results[key] = CompactVoicing(id: "\(kind == .triads ? "triad" : "diad")-\(key)", tones: tones, minFret: minFret, maxFret: maxFret, stringSet: strings.map { PitchClass(Tunings.standard.openMIDINotes[$0]).name() }.joined(separator: "–"), inversion: inversion)
                }
            }
        }
        return results.values.sorted {
            $0.minFret == $1.minFret
                ? ($0.maxFret == $1.maxFret ? $0.stringSet < $1.stringSet : $0.maxFret < $1.maxFret)
                : $0.minFret < $1.minFret
        }
    }

    private static func frets(for string: Int, pitchClass: PitchClass, fretCount: Int) -> [Int] {
        (0...fretCount).filter { PitchClass(Tunings.standard.openMIDINotes[string] + $0) == pitchClass }
    }

    private static func permutations(_ values: [Int]) -> [[Int]] {
        guard values.count > 1 else { return [values] }
        return values.indices.flatMap { index in
            permutations(Array(values[..<index] + values[(index + 1)...])).map { [values[index]] + $0 }
        }
    }

    private static func cartesian(_ values: [[Int]]) -> [[Int]] {
        values.reduce([[]]) { rows, values in
            rows.flatMap { row in values.map { row + [$0] } }
        }
    }
}
