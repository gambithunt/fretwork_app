import CoreAudio
import Foundation
import Observation

/// The macOS adapter: owns HAL device enumeration/selection, monitor routing and
/// the direct-path suggestion, and wraps the existing `AudioEngine` unchanged.
///
/// Everything here was lifted out of `AppState` so the shared model layer can
/// depend on `AudioControlling` instead of a concrete, CoreAudio-backed engine.
/// The engine itself is untouched (see the C-19 immutability note).
@MainActor @Observable
final class MacAudioController: AudioControlling {

    // MARK: - Mac-only device/monitor state (moved from AppState)

    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []
    var selectedInputDeviceID: AudioDeviceID?
    var selectedOutputDeviceID: AudioDeviceID?
    var monitorMuted = true { didSet { applyMonitorVolume() } }
    var monitorVolume: Double = 0.8 { didSet { applyMonitorVolume() } }

    // MARK: - AudioControlling

    var onEvent: (@MainActor @Sendable (AudioControllerEvent) -> Void)?

    /// How many times the audio graph has been built this session. Navigation
    /// must never move this — see `AppShellNavigationTests`.
    var graphBuildCount: Int { engine.graphBuildCount }

    /// The last error the engine reported, kept so the DEBUG capture tooling can
    /// explain why it cannot record. Mirrors the `errorMessage` `AppState`
    /// publishes from the same event; cleared on recovery and on `start()`.
    private(set) var lastErrorMessage: String?

#if DEBUG
    /// The sample-capture screen drives the recorder directly. It is a
    /// maintainer tool, so this is the one seam it gets rather than the
    /// recorder's state being folded into the ordinary UI state.
    var sampleRecorder: SampleRecorder { engine.sampleRecorder }

    func setSampleRecordingEnabled(_ value: Bool) {
        engine.setSampleRecordingEnabled(value)
    }

    /// Nil when the recorder is running. Otherwise, why not — so the capture
    /// window can say it plainly instead of waiting for a note that can never
    /// arrive.
    var sampleRecordingBlockedReason: String? {
        if selectedInputDeviceID == nil {
            return "No input device is selected. Choose one in the main Fretwork window."
        }
        if let lastErrorMessage {
            return "Audio is not running: \(lastErrorMessage)"
        }
        if !engine.sampleRecorder.isRunning {
            return "The recorder is not draining audio. Check the input device in the main Fretwork window, then reopen this one."
        }
        return nil
    }
#endif

    // MARK: - Stored dependencies

    private let engine = AudioEngine()
    private let deviceWatcher = AudioDeviceWatcher()
    private let store: PracticeStateStore
    /// Coalesces a burst of `deviceWatcher.onChange` notifications (a
    /// multi-stream interface unplugging can fire several in quick
    /// succession) into one rescan, and keeps the scan itself off the main
    /// actor — see `scheduleDeviceRefresh`.
    private var pendingDeviceRefresh: Task<Void, Never>?
    /// What the user actually chose. `selectedInput/OutputDeviceID` is only a
    /// resolution of these against whatever is plugged in right now.
    private var selectedInputUID: String?
    private var selectedOutputUID: String?

    /// Whether a saved output was restored, so a test can tell the "no saved
    /// device, fell back to the system default" case from the "restored what
    /// was saved" one.
    var selectedOutputUIDForTesting: String? { selectedOutputUID }

    init(store: PracticeStateStore) {
        self.store = store
        // Five engine callbacks fan into one event stream. Each hop to the
        // main actor is exactly the one `AppState` performed in its own
        // forwarding closures today — the note/chord callbacks already arrive
        // on the main actor from the workers, and the error/recovery/watchdog
        // callbacks do not, so the hop is preserved per callback rather than
        // added on top of one.
        engine.onUpdate = { [weak self] update in
            Task { @MainActor [weak self] in self?.onEvent?(.noteUpdate(update)) }
        }
        engine.onChordUpdate = { [weak self] update in
            Task { @MainActor [weak self] in self?.onEvent?(.chordUpdate(update)) }
        }
        engine.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.lastErrorMessage = message
                self?.onEvent?(.error(message))
            }
        }
        engine.onRecovered = { [weak self] in
            Task { @MainActor [weak self] in
                self?.lastErrorMessage = nil
                self?.onEvent?(.recovered)
            }
        }
        engine.onReconnecting = { [weak self] in
            Task { @MainActor [weak self] in self?.onEvent?(.reconnecting) }
        }
        // Picks up hardware plugged in after launch — e.g. an interface
        // connected once the app is already running — without the user
        // having to notice and hit Rescan themselves.
        deviceWatcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleDeviceRefresh() }
        }
        refreshDevices()
        restoreSelections()
    }

    // MARK: - AudioControlling lifecycle

    func start() -> Bool {
        guard let selectedInputDeviceID, let selectedOutputDeviceID else { return false }
        lastErrorMessage = nil
        engine.start(inputDeviceID: selectedInputDeviceID, outputDeviceID: selectedOutputDeviceID, monitorVolume: monitorMuted ? 0 : Float(monitorVolume))
        return true
    }

    func stop() { engine.stop() }

    func setChordDetectionEnabled(_ enabled: Bool) { engine.setChordDetectionEnabled(enabled) }

    func setSensitivity(_ value: Double) { engine.setSensitivity(value) }

    func prepareSamplePlayback(completion: (@Sendable (String?) -> Void)?) {
        engine.prepareSamplePlayback(completion: completion)
    }

    var isSamplePlaybackReady: Bool { engine.isSamplePlaybackReady }
    var isSampleLibraryLoaded: Bool { engine.isSampleLibraryLoaded }

    func playSample(string: Int, fret: Int, tuning: Tuning) {
        engine.playSample(string: string, fret: fret, tuning: tuning)
    }

    // MARK: - Device enumeration / selection

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
        let uid = inputDevices.first { $0.id == id }?.uid
        selectedInputUID = uid
        if uid != nil { store.update { $0.settings.inputDeviceUID = uid } }
        start()
    }

    func selectOutputDevice(_ id: AudioDeviceID?) {
        selectedOutputDeviceID = id
        let uid = outputDevices.first { $0.id == id }?.uid
        selectedOutputUID = uid
        if uid != nil { store.update { $0.settings.outputDeviceUID = uid } }
        start()
    }

    // MARK: - Refresh

    func refreshDevices() {
        applyDeviceLists(inputs: AudioDeviceEnumerator.inputDevices(), outputs: AudioDeviceEnumerator.outputDevices())
    }

    /// `AudioDeviceEnumerator`'s scan does several blocking Core Audio HAL
    /// calls, and a device disconnect is exactly when those can stall — a
    /// driver mid-teardown, or a multi-stream interface firing several
    /// change notifications in a burst. Doing that scan directly on the main
    /// actor (as a naive `deviceWatcher.onChange` handler would) is what
    /// used to read as the whole app freezing on unplug. This runs it on a
    /// detached task instead, and debounces so a burst of notifications
    /// coalesces into one scan rather than several stacked back to back.
    private func scheduleDeviceRefresh() {
        pendingDeviceRefresh?.cancel()
        pendingDeviceRefresh = Task.detached { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let inputs = AudioDeviceEnumerator.inputDevices()
            let outputs = AudioDeviceEnumerator.outputDevices()
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.applyDeviceLists(inputs: inputs, outputs: outputs)
            }
        }
    }

    private func applyDeviceLists(inputs: [AudioDevice], outputs: [AudioDevice]) {
        inputDevices = inputs
        outputDevices = outputs
        selectedInputDeviceID = Self.reresolve(id: selectedInputDeviceID, uid: selectedInputUID, in: inputDevices)
        selectedOutputDeviceID = Self.reresolve(id: selectedOutputDeviceID, uid: selectedOutputUID, in: outputDevices)
    }

    // MARK: - Persistence restore

    /// Resolves the saved devices once, at construction, and persists whatever
    /// the restore settled on.
    private func restoreSelections() {
        let settings = store.state.settings
        let restoredInput = restoreSelection(uid: settings.inputDeviceUID, legacyIDKey: "selectedInputDeviceID", from: inputDevices)
        selectedInputUID = restoredInput?.uid
        // Falls back to the system default rather than the first enumerated
        // device — see `AudioDeviceEnumerator.defaultDeviceID`. Only if even
        // that is unavailable does the list order decide.
        selectedInputDeviceID = restoredInput?.id
            ?? AudioDeviceEnumerator.defaultDeviceID(scope: kAudioDevicePropertyScopeInput)
                .flatMap { id in inputDevices.first { $0.id == id }?.id }
            ?? inputDevices.first?.id
        let restoredOutput = restoreSelection(uid: settings.outputDeviceUID, legacyIDKey: "selectedOutputDeviceID", from: outputDevices)
        selectedOutputUID = restoredOutput?.uid
        selectedOutputDeviceID = restoredOutput?.id
            ?? AudioDeviceEnumerator.defaultDeviceID(scope: kAudioDevicePropertyScopeOutput)
                .flatMap { id in outputDevices.first { $0.id == id }?.id }
            ?? outputDevices.first?.id
        // Persist whatever the restore resolved — which matters for the legacy
        // numeric-ID path, where the UID is only learned by looking at the
        // devices present. `update` writes nothing when nothing changed.
        let inputUID = selectedInputUID
        let outputUID = selectedOutputUID
        store.update {
            $0.settings.inputDeviceUID = inputUID
            $0.settings.outputDeviceUID = outputUID
        }
    }

    /// Prefers the stable UID, falling back once to the legacy stored
    /// `AudioDeviceID` so an existing selection survives the upgrade — that ID
    /// is only trusted if it still resolves to a device that is present.
    private func restoreSelection(uid: String?, legacyIDKey: String, from devices: [AudioDevice]) -> AudioDevice? {
        Self.restoreSelection(uid: uid, legacyID: store.legacyDeviceID(forKey: legacyIDKey), from: devices)
    }

    // MARK: - Pure device resolution

    /// An interface that is unplugged and plugged back in comes back under a
    /// different `AudioDeviceID`. Matching on the stable UID first means the
    /// user's actual choice survives that, instead of silently sliding onto
    /// whichever device happens to sort first — which is how a carefully
    /// chosen interface ends up quietly replaced by the built-in one.
    ///
    /// `nonisolated` so tests can exercise it with fabricated devices and no HAL.
    nonisolated static func reresolve(id: AudioDeviceID?, uid: String?, in devices: [AudioDevice]) -> AudioDeviceID? {
        if let id, devices.contains(where: { $0.id == id }) { return id }
        if let uid, let match = devices.first(where: { $0.uid == uid }) { return match.id }
        return devices.first?.id
    }

    /// Prefers the stable UID, falling back once to the legacy stored
    /// `AudioDeviceID` so an existing selection survives the upgrade — that ID
    /// is only trusted if it still resolves to a device that is present.
    ///
    /// `nonisolated` so tests can exercise it with fabricated devices and no HAL.
    nonisolated static func restoreSelection(uid: String?, legacyID: UInt32?, from devices: [AudioDevice]) -> AudioDevice? {
        if let uid, let match = devices.first(where: { $0.uid == uid }) {
            return match
        }
        if let legacyID, let match = devices.first(where: { $0.id == legacyID }) {
            return match
        }
        return nil
    }

    // MARK: - Monitor volume

    private func applyMonitorVolume() {
        engine.setMonitorVolume(monitorMuted ? 0 : Float(monitorVolume))
    }
}
