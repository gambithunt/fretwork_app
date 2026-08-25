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

        init() {}
    }

    /// Per-module state, added as each learning module lands. Every field must
    /// decode with a default, so introducing one stays a compatible change and
    /// a build that does not know about a module cannot wipe its neighbours.
    struct Modules: Codable, Equatable, Sendable {
        init() {}
    }
}

extension PracticeState.Settings: Codable {
    private enum CodingKeys: String, CodingKey {
        case tuningID, sensitivity, inputDeviceUID, outputDeviceUID
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
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tuningID.rawValue, forKey: .tuningID)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encodeIfPresent(inputDeviceUID, forKey: .inputDeviceUID)
        try container.encodeIfPresent(outputDeviceUID, forKey: .outputDeviceUID)
    }
}
