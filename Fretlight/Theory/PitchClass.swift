import Foundation

/// One of the twelve chromatic pitch classes, 0 = C.
///
/// A distinct type rather than a bare `Int` because this domain is almost
/// entirely small integers that mean different things — MIDI note, pitch
/// class, fret, string index, semitone interval, scale degree — and the ones
/// that get confused cost the most. A MIDI note and a pitch class are both
/// plausible-looking numbers whose confusion produces a chord that is wrong
/// by an octave-independent amount, which reads as a bad shape rather than as
/// a bug. Frets and string indices stay `Int`, named at the call site.
struct PitchClass: Hashable, Sendable {
    /// Always 0...11, whatever was passed in.
    let value: Int

    init(_ value: Int) {
        self.value = (value % 12 + 12) % 12
    }

    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    func name(_ style: NoteNameStyle = .sharp) -> String {
        switch style {
        case .sharp: Self.sharpNames[value]
        case .flat: Self.flatNames[value]
        }
    }

    /// The flat spelling, or nil for a pitch class whose two spellings are the
    /// same note letter — the naturals, which have no alias to offer.
    var enharmonicAlias: String? {
        let flat = Self.flatNames[value]
        return Self.sharpNames[value] == flat ? nil : flat
    }

    /// Wraps, so transposing past B returns to C rather than running off the
    /// end of the table.
    func transposed(by semitones: Int) -> PitchClass {
        PitchClass(value + semitones)
    }

    /// Every pitch class in order from C, for callers building a chromatic row.
    static let chromatic: [PitchClass] = (0..<12).map(PitchClass.init)
}

enum NoteNameStyle: Sendable {
    case sharp
    case flat
}
