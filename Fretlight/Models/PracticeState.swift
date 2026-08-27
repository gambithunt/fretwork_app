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

        init() {}
    }

    /// Per-module state, added as each learning module lands. Every field must
    /// decode with a default, so introducing one stays a compatible change and
    /// a build that does not know about a module cannot wipe its neighbours.
    struct Modules: Codable, Equatable, Sendable {
        var notes = Notes()
        var intervals = Intervals()
        var octaves = Octaves()

        init() {}

        private enum CodingKeys: String, CodingKey { case notes, intervals, octaves }

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
        case tuningID, sensitivity, inputDeviceUID, outputDeviceUID, isFretboardFlipped
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
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tuningID.rawValue, forKey: .tuningID)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encodeIfPresent(inputDeviceUID, forKey: .inputDeviceUID)
        try container.encodeIfPresent(outputDeviceUID, forKey: .outputDeviceUID)
        try container.encode(isFretboardFlipped, forKey: .isFretboardFlipped)
    }
}
