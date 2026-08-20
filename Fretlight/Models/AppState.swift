import Foundation
import Observation
import CoreAudio

enum DetectionMode: String, CaseIterable, Sendable {
    case notes = "Notes"
    case chords = "Chords"
}

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
    /// Notes and chords are read differently enough (a dialed-in single
    /// pitch vs. a held chord shape) that showing both readouts at once is
    /// clutter, not information — so this is exclusive, not an additive
    /// toggle. It also gates whether `ChordAnalysisWorker` does any work at
    /// all: an idle Notes-mode session shouldn't pay for a detector nobody
    /// is looking at.
    var detectionMode: DetectionMode = .notes {
        didSet {
            audioEngine.setChordDetectionEnabled(detectionMode == .chords)
            // A pinned chord/note only means anything while looking at the
            // fretboard in its own mode — leaving that mode and coming back
            // resumes live rather than silently reappearing with a stale
            // pin the player likely forgot they set.
            if detectionMode != .chords { pinnedChordHistoryID = nil }
            if detectionMode != .notes { pinnedNoteHistoryID = nil }
        }
    }
    var chordDisplay = ChordDisplayState()
    /// Distinct chords the player has actually strummed, most recent last.
    /// Deduplicated against the last *appended* entry rather than the raw
    /// worker feed — the worker republishes its locked chord every poll tick
    /// while a chord is held (see `ChordAnalysisWorker`'s settle/silence-hold
    /// logic), so a naive append-on-every-update would log the same chord
    /// dozens of times per strum.
    private(set) var chordHistory: [ChordHistoryEntry] = []
    private static let chordHistoryLimit = 10
    /// Set when the player taps a history chip to hold that chord's shape on
    /// the fretboard instead of the live feed. Cleared by tapping the same
    /// chip again, or automatically whenever detection mode leaves `.chords`
    /// (see `detectionMode`'s didSet) — never by the next live update, or
    /// studying a past shape would be undone by the player's own next strum.
    var pinnedChordHistoryID: UUID?
    /// Distinct notes the player has actually fretted, most recent last.
    /// Appended from `resolvePositions` at the same point a genuine note
    /// change is detected, so this needs no dedup logic of its own the way
    /// chord history does — a sustained note republishes through `publish`
    /// far more often than it changes, but `resolvePositions` only runs its
    /// body on an actual change.
    private(set) var noteHistory: [NoteHistoryEntry] = []
    private static let noteHistoryLimit = 10
    /// Set when the player taps a note-history chip to hold that note's
    /// position on the fretboard instead of the live feed. Same lifecycle as
    /// `pinnedChordHistoryID` — cleared by tapping again, or by leaving
    /// `.notes` mode.
    var pinnedNoteHistoryID: UUID?
    /// Purely a display orientation for `FretboardView` — doesn't touch the
    /// pitch pipeline or `GuitarTuning`'s string indices, just which row
    /// `BoardGeometry` draws each index at. Left un-persisted, same as
    /// `detectionMode`: a per-session display choice, not a saved setting.
    var isFretboardFlipped = false
    /// Where the current note is most likely being played, best candidate
    /// first. Derived here rather than on the analysis thread because it
    /// depends on playing history, not on the audio.
    private(set) var fretPositions: [RankedPosition] = []
    var errorMessage: String?
    private let audioEngine = AudioEngine()
    private let resolver = FretPositionResolver()
    private var resolvedMIDI: Int?
    private let deviceWatcher = AudioDeviceWatcher()
    /// How often the analysis worker's stream is allowed to reach the UI.
    ///
    /// Deliberately chosen here rather than inherited from the audio, because
    /// the two have nothing to do with each other: detection runs at ~30Hz
    /// because YIN needs that cadence, while every published update
    /// re-rasterises this window on the CPU — SwiftUI's display lists are not
    /// GPU-accelerated, so the whole visible area is redrawn each time.
    /// Measured on a 1402pt-wide board: publishing at 30Hz costs 50% of a
    /// core, at 12Hz 27%. Nothing in a tuner readout is worth 23% of a core to
    /// show twice as often.
    private static let displayInterval = Duration.seconds(1.0 / 12)
    private var lastPublish: ContinuousClock.Instant?
    /// Latency is measured as the age of the audio being analysed, so it
    /// carries every bit of scheduling jitter between the capture callback and
    /// the main actor. Raw, it never repeats a value twice — a readout that
    /// changes twelve times a second reads as noise, not as information, and
    /// on an idle machine there is nothing for it to be reporting. Smoothed
    /// and held for display only; the measurement itself is untouched.
    private var smoothedLatency: Double?
    private var shownLatency: Double?
    /// What the user actually chose. `selectedInput/OutputDeviceID` is only a
    /// resolution of these against whatever is plugged in right now.
    private var selectedInputUID: String?
    private var selectedOutputUID: String?

    init() {
        refreshDevices()
        audioEngine.onUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.publish(update)
            }
        }
        audioEngine.onChordUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.chordDisplay = update
                self?.appendToHistory(update.chord)
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

    /// The analysis worker republishes the held note about thirty times a
    /// second, but only a genuine change of note is a new event to score —
    /// feeding it every frame would let one sustained note walk the resolver's
    /// hand-position estimate along the neck.
    /// Rate-limits the worker's stream to `displayInterval`, except when the
    /// note itself changes: a new note is the one event a player is waiting to
    /// see, so it goes through immediately and the clock restarts from there.
    /// Everything else — level, cents, frequency — is a value the eye reads,
    /// not an event it waits for, and can sit until the next refresh.
    ///
    /// Dropping the updates in between is safe because another always follows
    /// within ~33ms; nothing here is the only carrier of a state change.
    private func publish(_ update: PitchDisplayState) {
        let now = ContinuousClock.now
        let noteChanged = update.note?.midiNote != display.note?.midiNote
        if !noteChanged, let lastPublish, now - lastPublish < Self.displayInterval { return }
        lastPublish = now
        var shown = update
        shown.latencyMilliseconds = stableLatency(update.latencyMilliseconds)
        display = shown
        resolvePositions(for: update.note)
    }

    /// Eased, then held until it has actually moved. The threshold is
    /// relative because the two monitoring paths live orders of magnitude
    /// apart: a millisecond of drift is the whole story at 2ms and beneath
    /// notice at 100ms.
    private func stableLatency(_ measured: Double) -> Double {
        let smoothed = smoothedLatency.map { $0 + 0.2 * (measured - $0) } ?? measured
        smoothedLatency = smoothed
        guard let shown = shownLatency else {
            shownLatency = smoothed
            return smoothed
        }
        if abs(smoothed - shown) >= max(0.4, shown * 0.05) { shownLatency = smoothed }
        return shownLatency ?? smoothed
    }

    private func appendToHistory(_ match: ChordMatch?) {
        chordHistory = Self.appending(match, to: chordHistory, limit: Self.chordHistoryLimit)
    }

    /// Pure dedup+cap step, kept free of actor isolation so it's unit
    /// -testable without standing up an `AppState`. Dedups against only the
    /// last entry — A→B→A logs both A's, since this is a strum log, not a
    /// "chords seen so far" set.
    nonisolated static func appending(_ match: ChordMatch?, to history: [ChordHistoryEntry], limit: Int) -> [ChordHistoryEntry] {
        guard let match, match.name != history.last?.match.name else { return history }
        var result = history + [ChordHistoryEntry(match: match)]
        if result.count > limit { result.removeFirst(result.count - limit) }
        return result
    }

    /// What `FretboardView` should render: the pinned history entry's chord
    /// if the player is holding one, otherwise the live feed.
    var displayedChord: ChordMatch? {
        if let pinnedChordHistoryID, let pinned = chordHistory.first(where: { $0.id == pinnedChordHistoryID }) {
            return pinned.match
        }
        return chordDisplay.chord
    }

    /// What `FretboardView` should render in Notes mode: the pinned history
    /// entry's note if the player is holding one, otherwise the live note.
    var displayedNote: MappedNote? {
        if let pinnedNoteHistoryID, let pinned = noteHistory.first(where: { $0.id == pinnedNoteHistoryID }) {
            return pinned.note
        }
        return display.note
    }

    /// The positions to mark for `displayedNote` — the pinned entry's frozen
    /// snapshot, or the live resolver output. Kept as a snapshot on the
    /// entry rather than re-resolved here, because `FretPositionResolver` is
    /// stateful hand-tracking and re-resolving a past note on tap would
    /// perturb the live estimate.
    var displayedPositions: [RankedPosition] {
        if let pinnedNoteHistoryID, let pinned = noteHistory.first(where: { $0.id == pinnedNoteHistoryID }) {
            return pinned.positions
        }
        return fretPositions
    }

    private func appendToNoteHistory(_ note: MappedNote, positions: [RankedPosition]) {
        noteHistory = Self.appending(note, positions: positions, to: noteHistory, limit: Self.noteHistoryLimit)
    }

    /// Pure dedup+cap step, mirroring `appending(_:to:limit:)` for chords.
    /// The dedup guard here is a defensive backstop, not the primary
    /// mechanism — `resolvePositions` already only calls this on a genuine
    /// midiNote change — but keeping it means this function's own contract
    /// doesn't depend on how its one caller happens to behave.
    nonisolated static func appending(_ note: MappedNote?, positions: [RankedPosition], to history: [NoteHistoryEntry], limit: Int) -> [NoteHistoryEntry] {
        guard let note, note.midiNote != history.last?.note.midiNote else { return history }
        var result = history + [NoteHistoryEntry(note: note, positions: positions)]
        if result.count > limit { result.removeFirst(result.count - limit) }
        return result
    }

    private func resolvePositions(for note: MappedNote?) {
        guard let note else {
            fretPositions = []
            resolvedMIDI = nil
            return
        }
        guard note.midiNote != resolvedMIDI else { return }
        resolvedMIDI = note.midiNote
        fretPositions = resolver.resolve(midiNote: note.midiNote)
        appendToNoteHistory(note, positions: fretPositions)
    }

    deinit { audioEngine.stop() }
}
