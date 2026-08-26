import SwiftUI

/// The app's colour vocabulary, mirroring the web app's CSS custom properties
/// in `../fretwork/src/app.css`.
///
/// Two separate scales, and keeping them separate is the point:
///
/// - **Note colours** are the app-wide visual identity of a *pitch*. One hue per
///   pitch class, used for dot fills, so a C is the same colour wherever it
///   appears and in whichever app.
/// - **Role colours** say what a note is *doing* in the current lesson — root,
///   third, fifth, another scale tone. The web's comment puts it well: dot fills
///   carry pitch identity, and "lesson-specific meaning belongs in rings,
///   outlines, and labels".
///
/// Keyed by pitch class rather than by note-name string. It was keyed by name
/// because there was no theory layer to ask; workstream 001 landed one, and a
/// string key cannot survive the app spelling a note `A♯` in one place and `B♭`
/// in another. `color(for:)` remains for callers that still hold a name.
///
/// Values are the web's hex verbatim, not eyeballed approximations — the point
/// of sharing a palette is that a shape looks identical in both apps.
enum NotePalette {
    /// One hue per pitch class, 0 = C.
    private static let notes: [Color] = [
        Color(hex: 0xe5564e), // C   red
        Color(hex: 0xe07a3e), // C♯  orange
        Color(hex: 0xd6a23c), // D   amber
        Color(hex: 0xc2bf4a), // D♯  olive
        Color(hex: 0x5bbf5b), // E   green
        Color(hex: 0x3fbf8c), // F   teal-green
        Color(hex: 0x3fb6c4), // F♯  cyan
        Color(hex: 0x3f8fd8), // G   blue
        Color(hex: 0x6a78dd), // G♯  indigo
        Color(hex: 0x9a6fdd), // A   purple
        Color(hex: 0xc45fc4), // A♯  magenta
        Color(hex: 0xe05a8f)  // B   pink
    ]

    static func color(for pitchClass: PitchClass) -> Color {
        notes[pitchClass.value]
    }

    static func color(forPitchClass value: Int) -> Color {
        notes[((value % 12) + 12) % 12]
    }

    /// For callers still holding a spelled name. Falls back rather than
    /// trapping: a name is user-facing text and may be spelled either way.
    static func color(for name: String) -> Color {
        guard let pitchClass = PitchClass(name: name) else { return .orange }
        return color(for: pitchClass)
    }

    // MARK: - Role colours

    /// What a note is doing in the lesson, as distinct from which note it is.
    enum Role: Sendable, CaseIterable {
        /// The note the shape is built from.
        case root
        /// The interval or third — what gives a chord its quality.
        case third
        /// The fifth.
        case fifth
        /// Another tone of the scale, with no special role in this lesson.
        case degree
        /// Pentatonic tones: the notes that are safe to solo with.
        case pentatonic
        /// In key, but outside the shape being taught. Deliberately grey: it is
        /// context, not content.
        case outsideShape
    }

    static func color(for role: Role) -> Color {
        switch role {
        case .root: Color(hex: 0x1d9e75)        // green
        case .third: Color(hex: 0x7f77dd)       // purple
        case .fifth: Color(hex: 0xd85a30)       // coral
        case .degree: Color(hex: 0x378add)      // blue
        case .pentatonic: Color(hex: 0xe8c34a)  // gold
        case .outsideShape: Color(hex: 0x8a8a99) // grey
        }
    }

    /// Primary actions. The web's `--fw-accent`.
    static let accent = Color(hex: 0x5dcaa5)
}

extension Color {
    /// 0xRRGGBB, so the values above can be compared against the web's CSS by
    /// eye without converting anything.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
