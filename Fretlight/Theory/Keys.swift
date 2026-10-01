import Foundation

/// A major key with its conventional spelling.
///
/// A `PitchClass` is enharmonic: value 3 is both D♯ and E♭, value 10 both A♯
/// and B♭, and which one is correct depends on the key. That is invisible
/// until the keys are arranged as they are on the circle of fifths, where the
/// flat half — D♭, A♭, E♭, B♭ and F — must be written with flats. Spelling
/// from the pitch class alone silently sharpens every one of them (E♭ major
/// comes out D♯, G, A♯), which is the defect this type exists to prevent.
///
/// It lives in Theory because a key is not a view concept: the circle, the
/// triad labels and the teaching copy all need the same answer.
struct Key: Hashable, Sendable {
    let tonic: PitchClass
    /// The tonic as conventionally written for this key, e.g. "E♭" or
    /// "F♯/G♭". The leading letter decides how the scale is spelled.
    let name: String

    /// The seven notes of the major scale, spelled letter by letter: F major
    /// is F G A B♭ C D E, never F G A A♯ C D E.
    var majorScaleNoteNames: [String] {
        Scales.major.spelled(from: tonic, tonicName: name)
    }

    /// The spelled name of `pitchClass`, if it is a degree of this major
    /// scale. Nil for a note outside the key.
    func majorScaleName(of pitchClass: PitchClass) -> String? {
        zip(Harmony.keyScalePitchClasses(root: tonic, major: true), majorScaleNoteNames)
            .first { $0.0 == pitchClass }?.1
    }

    /// The sixth degree, spelled, which is the relative minor's tonic — so
    /// B♭ major's relative minor is G minor and never A♯ minor.
    var relativeMinorName: String { majorScaleNoteNames[5] }
}

enum Keys {
    /// The twelve major keys in fifths order, C at the top, each with the
    /// spelling the circle conventionally uses. The pivot key at the bottom is
    /// labelled both ways; it is held as F♯ so its notes and its D♯ relative
    /// minor stay in the sharp half.
    static let circleOfFifths: [Key] = [
        Key(tonic: PitchClass(0), name: "C"),
        Key(tonic: PitchClass(7), name: "G"),
        Key(tonic: PitchClass(2), name: "D"),
        Key(tonic: PitchClass(9), name: "A"),
        Key(tonic: PitchClass(4), name: "E"),
        Key(tonic: PitchClass(11), name: "B"),
        Key(tonic: PitchClass(6), name: "F♯/G♭"),
        Key(tonic: PitchClass(1), name: "D♭"),
        Key(tonic: PitchClass(8), name: "A♭"),
        Key(tonic: PitchClass(3), name: "E♭"),
        Key(tonic: PitchClass(10), name: "B♭"),
        Key(tonic: PitchClass(5), name: "F")
    ]
}
