import Foundation

/// The narrow slice of persistent storage the store needs, so tests can supply
/// their own instead of writing into a real defaults domain.
protocol PracticeStorage: AnyObject {
    func documentData() -> Data?
    func writeDocument(_ data: Data)
    /// A value written by a build that predates the document.
    func legacyValue(forKey key: String) -> Any?
}

final class UserDefaultsPracticeStorage: PracticeStorage {
    private static let documentKey = "fretwork.practice-state"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func documentData() -> Data? {
        defaults.data(forKey: Self.documentKey)
    }

    func writeDocument(_ data: Data) {
        defaults.set(data, forKey: Self.documentKey)
    }

    func legacyValue(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }
}

/// Loads, validates and saves the one `PracticeState` document.
///
/// Loading never throws and never writes. A missing, corrupt, truncated or
/// future document all resolve to usable defaults, because the alternative —
/// refusing to launch over a settings file — is never the right trade for an
/// app whose settings are all recoverable in a few clicks.
@MainActor
final class PracticeStateStore {
    private let storage: PracticeStorage
    private(set) var state: PracticeState

    init(storage: PracticeStorage = UserDefaultsPracticeStorage()) {
        self.storage = storage
        state = Self.load(from: storage)
    }

    /// Mutates and persists in one step. A change that leaves the document
    /// identical writes nothing — the same compare-before-assign discipline
    /// the audio-rate properties follow, for the same reason: the cheapest
    /// write is the one that does not happen.
    func update(_ change: (inout PracticeState) -> Void) {
        var next = state
        change(&next)
        next.version = PracticeState.currentVersion
        guard next != state else { return }
        state = next
        guard let data = try? JSONEncoder().encode(state) else { return }
        storage.writeDocument(data)
    }

    /// The very first builds stored a numeric `AudioDeviceID`. It only means
    /// anything against the devices present right now, so resolving it needs
    /// the device list — which is `AppState`'s, not the store's.
    func legacyDeviceID(forKey key: String) -> UInt32? {
        storage.legacyValue(forKey: key) as? UInt32
    }

    private static func load(from storage: PracticeStorage) -> PracticeState {
        guard let data = storage.documentData() else {
            return migratedFromLegacyKeys(in: storage)
        }
        guard let decoded = try? JSONDecoder().decode(PracticeState.self, from: data) else {
            return PracticeState()
        }
        // A document from a newer build may use fields this one would drop on
        // the next write. Run on defaults rather than guess at it — and since
        // loading never writes, a user who downgrades and changes nothing
        // still has their newer document intact when they go forward again.
        guard decoded.version <= PracticeState.currentVersion else {
            return PracticeState()
        }
        return decoded
    }

    /// No document yet, so build one from the loose keys earlier builds wrote.
    /// Without this an existing user's chosen interface and sensitivity reset
    /// themselves on upgrade, which reads as the app having forgotten them.
    ///
    /// Deliberately writes nothing and deletes nothing: the document is
    /// persisted the first time the user actually changes something, so
    /// installing this build and rolling back costs nothing.
    private static func migratedFromLegacyKeys(in storage: PracticeStorage) -> PracticeState {
        var state = PracticeState()
        if let uid = storage.legacyValue(forKey: "selectedInputDeviceUID") as? String {
            state.settings.inputDeviceUID = uid
        }
        if let uid = storage.legacyValue(forKey: "selectedOutputDeviceUID") as? String {
            state.settings.outputDeviceUID = uid
        }
        if let value = storage.legacyValue(forKey: "sensitivity") as? Double, value.isFinite {
            state.settings.sensitivity = min(max(value, 0), 1)
        }
        return state
    }
}
