import Foundation

/// Everything the app remembers between launches, as one versioned document.
///
/// One document rather than the loose `UserDefaults` keys this replaces,
/// because the settings only mean anything together — a saved device UID is
/// uninterpretable without knowing which schema wrote it — and because a
/// single value is the only thing that can be validated, defaulted and reset
/// as a unit.
struct PracticeState: Codable, Equatable, Sendable {
    /// Bumped only for a change an older build cannot safely read. Adding a
    /// field is not such a change: every field decodes with a default, so a
    /// document written before it existed simply arrives with it unset. That
    /// is what lets each learning module add its own state later without
    /// invalidating everything already saved.
    static let currentVersion = 1

    var version: Int = currentVersion
    var settings: Settings = Settings()
    var modules: Modules = Modules()

    private enum CodingKeys: String, CodingKey {
        case version, settings, modules
    }

    init() {}

    /// Field by field, substituting a default for anything missing or
    /// unreadable. The synthesised initialiser would throw on the first bad
    /// value and take the whole document with it — losing a working device
    /// selection because a later field was malformed.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let stored = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? nil {
            version = stored
        }
        if let stored = (try? container.decodeIfPresent(Settings.self, forKey: .settings)) ?? nil {
            settings = stored
        }
        if let stored = (try? container.decodeIfPresent(Modules.self, forKey: .modules)) ?? nil {
            modules = stored
        }
    }
}

extension PracticeState {
    struct Settings: Equatable, Sendable {
        var tuningID: TuningID = .standard
        var sensitivity: Double = SensitivitySettings.defaultValue
        /// Device *UIDs*, never IDs. `AudioDevice.id` is reassigned by Core
        /// Audio across unplug and reboot; the UID is what survives, which is
        /// the whole reason a selection can be restored at all.
        var inputDeviceUID: String?
        var outputDeviceUID: String?
        /// Board orientation, applied to every board in the app.
        ///
        /// Was a per-session `AppState` flag that reset on every launch, which
        /// is the worst of both worlds: a player who prefers the player's-eye
        /// view had to re-flip it each time, and with ten module boards coming
        /// it has to be one preference applied everywhere rather than a toggle
        /// per board.
        ///
        /// False is the default board: Low E along the bottom, High E on top —
        /// tablature's convention, and the orientation the web app draws, so a
        /// shape looks identical in both.
        var isFretboardFlipped = false
        /// Shows the current detected pitch in the header of every learning
        /// module. Off by default so lesson screens remain focused unless the
        /// player explicitly wants continuous feedback while practising.
        var showsLiveNoteOnModules = false
        /// Adds a quiet halo to lesson dots whose pitch class matches the
        /// current live note. This is distinct from the header readout: a
        /// player may want the note named without also changing the visual
        /// hierarchy of every lesson board.
        var highlightsLiveNoteOnFretboards = false
        /// Explicitly chosen, anonymous product telemetry. This remains off
        /// until the player enables it in Settings; it is not bundled into the
        /// microphone permission or any other app preference.
        var sharesAnonymousUsageData = false

        init() {}
    }

    /// Per-module state, added as each learning module lands. Every field must
    /// decode with a default, so introducing one stays a compatible change and
    /// a build that does not know about a module cannot wipe its neighbours.
    struct Modules: Codable, Equatable, Sendable {
        var notes = Notes()
        var intervals = Intervals()
        var octaves = Octaves()
        var triads = Triads()
        var chords = Chords()
        var pentatonic = Pentatonic()
        var scales = Scales()
        var harmonizing = Harmonizing()
        var circle = Circle()
        var noteAssociation = NoteAssociation()

        init() {}

        private enum CodingKeys: String, CodingKey {
            case notes, intervals, octaves, triads, chords, pentatonic, scales, harmonizing, circle
            case noteAssociation
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init()
            if let stored = (try? container.decodeIfPresent(Notes.self, forKey: .notes)) ?? nil {
                notes = stored
            }
            if let stored = (try? container.decodeIfPresent(Intervals.self, forKey: .intervals)) ?? nil {
                intervals = stored
            }
            if let stored = (try? container.decodeIfPresent(Octaves.self, forKey: .octaves)) ?? nil {
                octaves = stored
            }
            if let stored = (try? container.decodeIfPresent(Triads.self, forKey: .triads)) ?? nil {
                triads = stored
            }
            if let stored = (try? container.decodeIfPresent(Chords.self, forKey: .chords)) ?? nil {
                chords = stored
            }
            if let stored = (try? container.decodeIfPresent(Pentatonic.self, forKey: .pentatonic)) ?? nil {
                pentatonic = stored
            }
            if let stored = (try? container.decodeIfPresent(Scales.self, forKey: .scales)) ?? nil {
                scales = stored
            }
            if let stored = (try? container.decodeIfPresent(Harmonizing.self, forKey: .harmonizing)) ?? nil {
                harmonizing = stored
            }
            if let stored = (try? container.decodeIfPresent(Circle.self, forKey: .circle)) ?? nil {
                circle = stored
            }
            if let stored = (try? container.decodeIfPresent(NoteAssociation.self, forKey: .noteAssociation)) ?? nil {
                noteAssociation = stored
            }
        }

        /// Note association — the capstone. Key, focused chord, which layers
        /// are on, and which progression to practise.
        struct NoteAssociation: Codable, Equatable, Sendable {
            var rootPitchClass: Int = 0
            var isMajor: Bool = true
            /// 0...6.
            var chordDegree: Int = 0
            var progressionID: String = ProgressionID.pop1564.rawValue
            var loop: Bool = false
            /// `notes` or `degrees`.
            var labelMode: String = "notes"
            var showsChordTones: Bool = true
            var showsPentatonic: Bool = true
            var showsScale: Bool = true

            init() {}

            private enum CodingKeys: String, CodingKey {
                case rootPitchClass, isMajor, chordDegree, progressionID, loop, labelMode
                case showsChordTones, showsPentatonic, showsScale
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .rootPitchClass)) ?? nil {
                    rootPitchClass = ((value % 12) + 12) % 12
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .isMajor)) ?? nil {
                    isMajor = value
                }
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .chordDegree)) ?? nil {
                    chordDegree = min(max(value, 0), 6)
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .progressionID)) ?? nil,
                   ProgressionID(rawValue: value) != nil {
                    progressionID = value
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .loop)) ?? nil {
                    loop = value
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .labelMode)) ?? nil,
                   ["notes", "degrees"].contains(value) {
                    labelMode = value
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .showsChordTones)) ?? nil {
                    showsChordTones = value
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .showsPentatonic)) ?? nil {
                    showsPentatonic = value
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .showsScale)) ?? nil {
                    showsScale = value
                }
            }
        }

        /// Circle of fifths: which key is selected.
        struct Circle: Codable, Equatable, Sendable {
            var selectedPitchClass: Int = 0

            init() {}

            private enum CodingKeys: String, CodingKey { case selectedPitchClass }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .selectedPitchClass)) ?? nil {
                    selectedPitchClass = ((value % 12) + 12) % 12
                }
            }
        }

        /// Harmonizing: the key, and which degree of it is being looked at.
        struct Harmonizing: Codable, Equatable, Sendable {
            var keyRootPitchClass: Int = 0
            var isMajor: Bool = true
            /// 0...6 — I through vii.
            var degree: Int = 0

            init() {}

            private enum CodingKeys: String, CodingKey { case keyRootPitchClass, isMajor, degree }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .keyRootPitchClass)) ?? nil {
                    keyRootPitchClass = ((value % 12) + 12) % 12
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .isMajor)) ?? nil {
                    isMajor = value
                }
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .degree)) ?? nil {
                    degree = min(max(value, 0), 6)
                }
            }
        }

        /// Scales: root, which scale, how the dots are labelled, and whether a
        /// run goes up or up-and-back-down.
        struct Scales: Codable, Equatable, Sendable {
            var rootPitchClass: Int = 0
            /// `major` or `naturalMinor`.
            var quality: String = OneOctaveScaleQuality.major.rawValue
            /// `notes` or `degrees` — whether a dot shows what the note *is* or
            /// what it *does*. Both are worth practising and neither is a
            /// default the other can stand in for.
            var labelMode: String = "notes"
            /// `ascending` or `upDown`.
            var direction: String = "ascending"

            init() {}

            private enum CodingKeys: String, CodingKey { case rootPitchClass, quality, labelMode, direction }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .rootPitchClass)) ?? nil {
                    rootPitchClass = ((value % 12) + 12) % 12
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .quality)) ?? nil,
                   OneOctaveScaleQuality(rawValue: value) != nil {
                    quality = value
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .labelMode)) ?? nil,
                   ["notes", "degrees"].contains(value) {
                    labelMode = value
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .direction)) ?? nil,
                   ["ascending", "upDown"].contains(value) {
                    direction = value
                }
            }
        }

        /// Pentatonic: root, quality, which of the five boxes, and how many
        /// boxes are on screen at once.
        ///
        /// The guided run itself is absent, as workstream 006 requires: guided
        /// playback state stays transient.
        struct Pentatonic: Codable, Equatable, Sendable {
            var rootPitchClass: Int = 9
            /// `minor` or `major`.
            var quality: String = PentatonicQuality.minorPentatonic.rawValue
            /// 0...4, matching `ScaleShapes.pentatonicPosition` and the web's
            /// own saved value. Displayed as 1–5; stored as the index it is.
            var position: Int = 0
            /// `single`, `pair` or `path`.
            var displayMode: String = "single"
            /// The lowest box shown when more than one is. 0-based, as above.
            var displayStart: Int = 0

            init() {}

            private enum CodingKeys: String, CodingKey { case rootPitchClass, quality, position, displayMode, displayStart }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .rootPitchClass)) ?? nil {
                    rootPitchClass = ((value % 12) + 12) % 12
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .quality)) ?? nil,
                   PentatonicQuality(rawValue: value) != nil {
                    quality = value
                }
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .position)) ?? nil {
                    position = min(max(value, 0), 4)
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .displayMode)) ?? nil,
                   ["single", "pair", "path"].contains(value) {
                    displayMode = value
                }
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .displayStart)) ?? nil {
                    displayStart = min(max(value, 0), 4)
                }
            }
        }

        /// Chords: root, which formula, and which voicing along the neck.
        struct Chords: Codable, Equatable, Sendable {
            var rootPitchClass: Int = 0
            /// A formula `id`, not an index — the catalogue has sixteen and may
            /// gain more.
            var formulaID: String = "maj"
            /// A voicing's own id rather than an index into the list, because
            /// the list changes length with the formula and an index would
            /// silently land on a different shape.
            var positionID: String = ""

            init() {}

            private enum CodingKeys: String, CodingKey { case rootPitchClass, formulaID, positionID }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .rootPitchClass)) ?? nil {
                    rootPitchClass = ((value % 12) + 12) % 12
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .formulaID)) ?? nil,
                   ChordFormulas.formula(id: value) != nil {
                    formulaID = value
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .positionID)) ?? nil {
                    positionID = value
                }
            }
        }

        /// Triads: the largest of the reference modules, and the one with the
        /// most to remember between visits.
        ///
        /// The path settings are kept separate from the shape settings on
        /// purpose — they are two different exercises that happen to share a
        /// screen, and returning to one should not have disturbed the other.
        struct Triads: Codable, Equatable, Sendable {
            var rootPitchClass: Int = 0
            /// A chord's `short`, not an index, for the same reason intervals
            /// store `short`: a catalogue that gains an entry must not silently
            /// re-point a saved selection.
            var triadShort: String = "maj"
            var doubleStopID: String = "maj3"
            /// `shapes`, `inversions` or `doubleStops` — which of the three
            /// ways of looking at a triad is on screen.
            var view: String = "shapes"
            /// Which voicing along the neck.
            var position: Int = 0

            var pathKeyRoot: Int = 0
            var pathIsMajor: Bool = true
            var pathStringSet: String = TriadPathStringSet.dgb.rawValue
            var pathStep: Int = 0
            var isPathMode: Bool = false

            init() {}

            private enum CodingKeys: String, CodingKey {
                case rootPitchClass, triadShort, doubleStopID, view, position
                case pathKeyRoot, pathIsMajor, pathStringSet, pathStep, isPathMode
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .rootPitchClass)) ?? nil {
                    rootPitchClass = ((value % 12) + 12) % 12
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .triadShort)) ?? nil,
                   Fretwork.Triads.all.contains(where: { $0.short == value }) {
                    triadShort = value
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .doubleStopID)) ?? nil,
                   DoubleStops.all.contains(where: { $0.id == value }) {
                    doubleStopID = value
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .view)) ?? nil,
                   ["shapes", "inversions", "doubleStops"].contains(value) {
                    view = value
                }
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .position)) ?? nil {
                    position = max(0, value)
                }
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .pathKeyRoot)) ?? nil {
                    pathKeyRoot = ((value % 12) + 12) % 12
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .pathIsMajor)) ?? nil {
                    pathIsMajor = value
                }
                if let value = (try? container.decodeIfPresent(String.self, forKey: .pathStringSet)) ?? nil,
                   TriadPathStringSet(rawValue: value) != nil {
                    pathStringSet = value
                }
                if let value = (try? container.decodeIfPresent(Int.self, forKey: .pathStep)) ?? nil {
                    pathStep = max(0, value)
                }
                if let value = (try? container.decodeIfPresent(Bool.self, forKey: .isPathMode)) ?? nil {
                    isPathMode = value
                }
            }
        }

        /// Octaves: the root being traced and which of its shapes is anchored.
        ///
        /// The challenge's progress is deliberately absent — a half-finished
        /// round is not something to resume days later, and workstream 006
        /// states that guided playback state stays transient.
        struct Octaves: Codable, Equatable, Sendable {
            var rootPitchClass: Int = 0
            var anchor: String = "0:8"

            init() {}

            private enum CodingKeys: String, CodingKey { case rootPitchClass, anchor }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let stored = (try? container.decodeIfPresent(Int.self, forKey: .rootPitchClass)) ?? nil {
                    rootPitchClass = ((stored % 12) + 12) % 12
                }
                if let stored = (try? container.decodeIfPresent(String.self, forKey: .anchor)) ?? nil {
                    anchor = stored
                }
            }
        }

        /// Intervals: which root, which interval, and where on the neck the
        /// player last anchored it.
        ///
        /// The anchor is stored as `"string:fret"` like the Notes board, and it
        /// matters because an interval shape means nothing in the abstract —
        /// the point of the module is where it sits under the hand.
        struct Intervals: Codable, Equatable, Sendable {
            var rootPitchClass: Int = 0
            /// The interval's `short`, not its index: an index would silently
            /// re-point at a different interval if the catalogue ever gained
            /// one.
            var intervalShort: String = "P5"
            var anchor: String = "1:3"

            init() {}

            private enum CodingKeys: String, CodingKey { case rootPitchClass, intervalShort, anchor }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let stored = (try? container.decodeIfPresent(Int.self, forKey: .rootPitchClass)) ?? nil {
                    rootPitchClass = ((stored % 12) + 12) % 12
                }
                if let stored = (try? container.decodeIfPresent(String.self, forKey: .intervalShort)) ?? nil,
                   Intervals.isKnown(stored) {
                    intervalShort = stored
                }
                if let stored = (try? container.decodeIfPresent(String.self, forKey: .anchor)) ?? nil {
                    anchor = stored
                }
            }

            /// A retired interval name falls back rather than leaving the
            /// module pointing at nothing.
            static func isKnown(_ short: String) -> Bool {
                Fretwork.Intervals.all.contains { $0.short == short }
            }
        }

        /// Notes-on-the-fretboard: which positions the player has put on the
        /// neck.
        ///
        /// Stored as `"string:fret"` strings, matching the web app's key format
        /// exactly, so the same saved board means the same thing in both and a
        /// future sync has nothing to translate.
        struct Notes: Codable, Equatable, Sendable {
            var placed: [String] = Notes.defaultPlaced

            init() {}

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init()
                if let stored = (try? container.decodeIfPresent([String].self, forKey: .placed)) ?? nil {
                    placed = stored
                }
            }

            private enum CodingKeys: String, CodingKey { case placed }

            /// Every C on the neck, as the web app opens. A board that starts
            /// empty teaches nothing on arrival; one note in every octave shows
            /// the pattern the module is about before the player touches it.
            static let defaultPlaced: [String] = Positions
                .findAll(pitchClasses: [PitchClass(0)], fretCount: LearningModule.notes.highestFret)
                .map { "\($0.string):\($0.fret)" }
        }
    }
}

extension PracticeState.Settings: Codable {
    private enum CodingKeys: String, CodingKey {
        case tuningID, sensitivity, inputDeviceUID, outputDeviceUID, isFretboardFlipped, showsLiveNoteOnModules, highlightsLiveNoteOnFretboards, sharesAnonymousUsageData
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        // An unrecognised tuning is the likeliest field to go stale — a name
        // could be retired between builds — so it falls back rather than
        // throwing, which a synthesised enum decode would do.
        if let raw = (try? container.decodeIfPresent(String.self, forKey: .tuningID)) ?? nil,
           let tuning = TuningID(rawValue: raw) {
            tuningID = tuning
        }
        if let value = (try? container.decodeIfPresent(Double.self, forKey: .sensitivity)) ?? nil,
           value.isFinite {
            sensitivity = min(max(value, 0), 1)
        }
        inputDeviceUID = (try? container.decodeIfPresent(String.self, forKey: .inputDeviceUID)) ?? nil
        outputDeviceUID = (try? container.decodeIfPresent(String.self, forKey: .outputDeviceUID)) ?? nil
        if let value = (try? container.decodeIfPresent(Bool.self, forKey: .isFretboardFlipped)) ?? nil {
            isFretboardFlipped = value
        }
        if let value = (try? container.decodeIfPresent(Bool.self, forKey: .showsLiveNoteOnModules)) ?? nil {
            showsLiveNoteOnModules = value
        }
        if let value = (try? container.decodeIfPresent(Bool.self, forKey: .highlightsLiveNoteOnFretboards)) ?? nil {
            highlightsLiveNoteOnFretboards = value
        }
        if let value = (try? container.decodeIfPresent(Bool.self, forKey: .sharesAnonymousUsageData)) ?? nil {
            sharesAnonymousUsageData = value
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tuningID.rawValue, forKey: .tuningID)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encodeIfPresent(inputDeviceUID, forKey: .inputDeviceUID)
        try container.encodeIfPresent(outputDeviceUID, forKey: .outputDeviceUID)
        try container.encode(isFretboardFlipped, forKey: .isFretboardFlipped)
        try container.encode(showsLiveNoteOnModules, forKey: .showsLiveNoteOnModules)
        try container.encode(highlightsLiveNoteOnFretboards, forKey: .highlightsLiveNoteOnFretboards)
        try container.encode(sharesAnonymousUsageData, forKey: .sharesAnonymousUsageData)
    }
}
