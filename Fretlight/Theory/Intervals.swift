import Foundation

enum IntervalUseCategory: String, Sendable {
    case chords
    case melody
    case riffs
    case tension
}

struct IntervalUse: Sendable, Equatable {
    let label: String
    let category: IntervalUseCategory
}

struct Interval: Sendable, Equatable {
    let name: String
    let short: String
    let semitones: Int
    let feel: String
    let uses: [IntervalUse]
    let exercise: String
}

enum Intervals: Sendable {
    static let all: [Interval] = [
        Interval(name: "Minor 2nd", short: "m2", semitones: 1, feel: "The most tense, dissonant sound in music — think the Jaws theme. One fret apart.", uses: [IntervalUse(label: "Chromatic approaches", category: .melody), IntervalUse(label: "Tension and release", category: .tension), IntervalUse(label: "Dissonant riffs", category: .riffs)], exercise: "Play {root}, then {target}, then return to {root}. Let the half-step tension resolve."),
        Interval(name: "Major 2nd", short: "M2", semitones: 2, feel: "Two frets apart — adjacent notes in a scale. Smooth and stepwise.", uses: [IntervalUse(label: "Scale movement", category: .melody), IntervalUse(label: "Sus2 and add9 sounds", category: .chords), IntervalUse(label: "Stepwise melodies", category: .melody)], exercise: "Alternate {root} and {target} evenly, then move the same two-fret idea to another root."),
        Interval(name: "Minor 3rd", short: "m3", semitones: 3, feel: "Three frets apart — the gap that defines a minor chord. Dark and emotional.", uses: [IntervalUse(label: "Minor chords", category: .chords), IntervalUse(label: "Blues phrases", category: .riffs), IntervalUse(label: "Minor melodies", category: .melody)], exercise: "Play {root} and {target} separately, then together. Listen for the minor character."),
        Interval(name: "Major 3rd", short: "M3", semitones: 4, feel: "Four frets apart — the gap that defines a major chord. Bright and open.", uses: [IntervalUse(label: "Major chords", category: .chords), IntervalUse(label: "Major melodies", category: .melody), IntervalUse(label: "Double-stops", category: .riffs)], exercise: "Play {root} and {target} together, then move the shape to two other root positions."),
        Interval(name: "Perfect 4th", short: "P4", semitones: 5, feel: "Five frets — strong and stable. The opening of 'Here Comes the Bride'.", uses: [IntervalUse(label: "Suspended chords", category: .chords), IntervalUse(label: "Guitar riffs", category: .riffs), IntervalUse(label: "Melodic movement", category: .melody)], exercise: "Move from {root} up to {target} and back. Keep the shape clean and even."),
        Interval(name: "Tritone", short: "TT", semitones: 6, feel: "Six frets — the restless 'devil's interval'. Wants badly to resolve.", uses: [IntervalUse(label: "Dominant-chord tension", category: .tension), IntervalUse(label: "Diminished sounds", category: .chords), IntervalUse(label: "Unstable riffs", category: .riffs)], exercise: "Play {root} and {target} together, then resolve {target} one fret in either direction."),
        Interval(name: "Perfect 5th", short: "P5", semitones: 7, feel: "Seven frets — powerful and open. The backbone of every power chord.", uses: [IntervalUse(label: "Power chords", category: .chords), IntervalUse(label: "Major and minor triads", category: .chords), IntervalUse(label: "Strong riffs", category: .riffs)], exercise: "Play {root} and {target} together. Move the same shape to two other root positions."),
        Interval(name: "Minor 6th", short: "m6", semitones: 8, feel: "Eight frets — bittersweet, yearning. A softer kind of tension.", uses: [IntervalUse(label: "Natural-minor colour", category: .tension), IntervalUse(label: "Dramatic melodies", category: .melody), IntervalUse(label: "Tense chord voicings", category: .chords)], exercise: "Leap from {root} to {target}, pause, then descend to {root}. Listen to the dramatic pull."),
        Interval(name: "Major 6th", short: "M6", semitones: 9, feel: "Nine frets — sweet and warm. The 'My Bonnie' leap.", uses: [IntervalUse(label: "Major-scale melodies", category: .melody), IntervalUse(label: "Sixth chords", category: .chords), IntervalUse(label: "Harmonized lines", category: .melody)], exercise: "Play {root} and {target} together, then alternate them as a warm two-note melody."),
        Interval(name: "Minor 7th", short: "m7", semitones: 10, feel: "Ten frets — bluesy and unresolved. Built into every dominant 7 chord.", uses: [IntervalUse(label: "Dominant 7 chords", category: .chords), IntervalUse(label: "Minor 7 chords", category: .chords), IntervalUse(label: "Blues and funk", category: .riffs)], exercise: "Play {root}, jump to {target}, then return to {root}. Keep the upper note unresolved before returning."),
        Interval(name: "Major 7th", short: "M7", semitones: 11, feel: "Eleven frets — lush and dreamy, one semitone shy of home.", uses: [IntervalUse(label: "Major 7 chords", category: .chords), IntervalUse(label: "Leading-tone resolution", category: .tension), IntervalUse(label: "Jazz colour", category: .tension)], exercise: "Play {root} and {target} together, then move {target} up one fret to the octave."),
        Interval(name: "Octave", short: "P8", semitones: 12, feel: "Twelve frets — the same note, higher. Total resolution.", uses: [IntervalUse(label: "Octave riffs", category: .riffs), IntervalUse(label: "Melody doubling", category: .melody), IntervalUse(label: "Changing register", category: .melody)], exercise: "Alternate the low and high {root}. Then move the octave shape to two other notes.")
    ]
}
