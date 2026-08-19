import Foundation
import Observation
import CoreAudio

@MainActor @Observable
final class AppState {
    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []
    var selectedInputDeviceID: AudioDeviceID?
    var selectedOutputDeviceID: AudioDeviceID?
    var monitorMuted = true { didSet { applyMonitorVolume() } }
    var monitorVolume: Double = 0.8 { didSet { applyMonitorVolume() } }
    var sensitivity: Double = SensitivitySettings.defaultValue { didSet { applySensitivity() } }
    var display = PitchDisplayState()
    var errorMessage: String?
    private let audioEngine = AudioEngine()
    private let deviceWatcher = AudioDeviceWatcher()
    /// What the user actually chose. `selectedInput/OutputDeviceID` is only a
    /// resolution of these against whatever is plugged in right now.
    private var selectedInputUID: String?
    private var selectedOutputUID: String?

    init() {
        refreshDevices()
        audioEngine.onUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.display = update
            }
        }
        audioEngine.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.errorMessage = message
            }
        }
        audioEngine.onRecovered = { [weak self] in
            Task { @MainActor [weak self] in
                self?.errorMessage = nil
            }
        }
        // Picks up hardware plugged in after launch — e.g. an interface
        // connected once the app is already running — without the user
        // having to notice and hit Rescan themselves.
        deviceWatcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        let restoredInput = Self.restoreSelection(uidKey: "selectedInputDeviceUID", legacyIDKey: "selectedInputDeviceID", from: inputDevices)
        selectedInputUID = restoredInput?.uid
        selectedInputDeviceID = restoredInput?.id ?? inputDevices.first?.id
        let restoredOutput = Self.restoreSelection(uidKey: "selectedOutputDeviceUID", legacyIDKey: "selectedOutputDeviceID", from: outputDevices)
        selectedOutputUID = restoredOutput?.uid
        selectedOutputDeviceID = restoredOutput?.id ?? outputDevices.first?.id
        if let saved = UserDefaults.standard.object(forKey: "sensitivity") as? Double {
            sensitivity = saved
        }
    }

    func refreshDevices() {
        inputDevices = AudioDeviceEnumerator.inputDevices()
        outputDevices = AudioDeviceEnumerator.outputDevices()
        selectedInputDeviceID = Self.reresolve(id: selectedInputDeviceID, uid: selectedInputUID, in: inputDevices)
        selectedOutputDeviceID = Self.reresolve(id: selectedOutputDeviceID, uid: selectedOutputUID, in: outputDevices)
    }

    /// An interface that is unplugged and plugged back in comes back under a
    /// different `AudioDeviceID`. Matching on the stable UID first means the
    /// user's actual choice survives that, instead of silently sliding onto
    /// whichever device happens to sort first — which is how a carefully
    /// chosen interface ends up quietly replaced by the built-in one.
    private static func reresolve(id: AudioDeviceID?, uid: String?, in devices: [AudioDevice]) -> AudioDeviceID? {
        if let id, devices.contains(where: { $0.id == id }) { return id }
        if let uid, let match = devices.first(where: { $0.uid == uid }) { return match.id }
        return devices.first?.id
    }

    /// Prefers the stable UID, falling back once to the legacy stored
    /// `AudioDeviceID` so an existing selection survives the upgrade — that ID
    /// is only trusted if it still resolves to a device that is present.
    private static func restoreSelection(uidKey: String, legacyIDKey: String, from devices: [AudioDevice]) -> AudioDevice? {
        if let uid = UserDefaults.standard.string(forKey: uidKey),
           let match = devices.first(where: { $0.uid == uid }) {
            return match
        }
        if let legacy = UserDefaults.standard.object(forKey: legacyIDKey) as? UInt32,
           let match = devices.first(where: { $0.id == legacy }) {
            UserDefaults.standard.set(match.uid, forKey: uidKey)
            return match
        }
        return nil
    }

    /// Non-nil when the selected input device could also be doing the
    /// playback but isn't. That pairing is what unlocks single-engine duplex
    /// monitoring, and it is worth a good deal of latency — but nothing in the
    /// two separate device pickers hints that matching them matters, so offer
    /// it explicitly rather than leaving it to be discovered.
    var directMonitoringCandidate: AudioDevice? {
        guard let selectedInputDeviceID,
              selectedInputDeviceID != selectedOutputDeviceID,
              AudioDeviceEnumerator.isDuplexCapable(selectedInputDeviceID)
        else { return nil }
        return outputDevices.first { $0.id == selectedInputDeviceID }
    }

    func useInputDeviceForOutput() {
        guard let candidate = directMonitoringCandidate else { return }
        selectOutputDevice(candidate.id)
    }

    func selectInputDevice(_ id: AudioDeviceID?) {
        selectedInputDeviceID = id
        selectedInputUID = inputDevices.first { $0.id == id }?.uid
        if let uid = selectedInputUID { UserDefaults.standard.set(uid, forKey: "selectedInputDeviceUID") }
        start()
    }

    func selectOutputDevice(_ id: AudioDeviceID?) {
        selectedOutputDeviceID = id
        selectedOutputUID = outputDevices.first { $0.id == id }?.uid
        if let uid = selectedOutputUID { UserDefaults.standard.set(uid, forKey: "selectedOutputDeviceUID") }
        start()
    }

    private func applyMonitorVolume() {
        audioEngine.setMonitorVolume(monitorMuted ? 0 : Float(monitorVolume))
    }

    private func applySensitivity() {
        audioEngine.setSensitivity(sensitivity)
        UserDefaults.standard.set(sensitivity, forKey: "sensitivity")
    }

    func start() {
        guard let selectedInputDeviceID, let selectedOutputDeviceID else { return }
        errorMessage = nil
        audioEngine.start(inputDeviceID: selectedInputDeviceID, outputDeviceID: selectedOutputDeviceID, monitorVolume: monitorMuted ? 0 : Float(monitorVolume))
    }

    func retryAudio() { start() }

    deinit { audioEngine.stop() }
}
