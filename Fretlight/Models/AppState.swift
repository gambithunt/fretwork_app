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
            // The two modes read clarity from different signals (a resolved
            // note vs. a resolved chord match), so a hint earned in one mode
            // means nothing in the other — carrying it across a switch would
            // either falsely persist or falsely vanish.
            unclearSignalSince = nil
            unclearSignalMessage = nil
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
    /// Chosen against a measurement (offscreen NSHostingView harness, this
    /// project's usual way to size things without a real display), not a
    /// guess: 16 chips of realistic chord names fit inside the window's own
    /// minimum content width without scrolling; only the pathological case
    /// of every single entry being the longest possible label
    /// (root+"maj7"/"sus4", e.g. "C♯maj7") pushes past it, at which point
    /// `HistoryStrip`'s scroll fallback (not a hard cap) takes over instead
    /// of clipping.
    private static let chordHistoryLimit = 16
    /// Set when the player taps a history chip to hold that chord's shape on
    /// the fretboard instead of the live feed. Cleared by tapping the same
    /// chip again, or automatically whenever detection mode leaves `.chords`
    /// (see `detectionMode`'s didSet) — never by the next live update, or
    /// studying a past shape would be undone by the player's own next strum.
    var pinnedChordHistoryID: UUID?
    /// Every note the player has actually fretted, in order — including the
    /// same pitch hit twice in a row, which counts as two entries (this is
    /// a strum/pick log, not a "notes seen" set). Appended from
    /// `resolvePositions` after a short settle window (see
    /// `scheduleHistoryAppend`) whenever either the pitch changes or
    /// `detectRepick` catches a fresh pick attack on the same pitch. The
    /// settle window exists because the raw pitch estimate can swing
    /// through a wrong harmonic/octave for a few hops during a pluck's
    /// attack before settling — each swing is its own trigger for this, so
    /// logging immediately would turn one pluck into several entries.
    private(set) var noteHistory: [NoteHistoryEntry] = []
    /// Note labels ("A♯2") are shorter than chord labels, so the same 16
    /// that's measured safe for `chordHistoryLimit` is even more so here —
    /// kept equal for one consistent density between the two modes rather
    /// than two arbitrary numbers.
    private static let noteHistoryLimit = 16
    /// Set when the player taps a note-history chip to hold that note's
    /// position on the fretboard instead of the live feed. Same lifecycle as
    /// `pinnedChordHistoryID` — cleared by tapping again, or by leaving
    /// `.notes` mode.
    var pinnedNoteHistoryID: UUID?
    /// Purely a display orientation for `FretboardView` — doesn't touch the
    /// pitch pipeline or `GuitarTuning`'s string indices, just which row
    /// `BoardGeometry` draws each index at. Left un-persisted, same as
    /// `detectionMode`: a per-session display choice, not a saved setting.
    ///
    /// False is the default board: Low E along the bottom, High E on top —
    /// tablature's convention (pitch rises up the page), and the same
    /// orientation the web app draws, so a shape looks identical in both.
    var isFretboardFlipped = false
    /// Where the current note is most likely being played, best candidate
    /// first. Derived here rather than on the analysis thread because it
    /// depends on playing history, not on the audio.
    private(set) var fretPositions: [RankedPosition] = []
    var errorMessage: String?
    /// True from the moment `AudioEngine` starts an automatic recovery
    /// attempt until it either succeeds (`onRecovered`) or gives up
    /// (`onError`). Distinct from `errorMessage`: that only appears once
    /// recovery has been exhausted, which otherwise leaves the UI showing
    /// nothing — audio dead, meter silent, no explanation — for the whole
    /// multi-second retry window. Surfacing this instead is what turns that
    /// window from "looks frozen" into "visibly reconnecting".
    var isReconnecting = false
    /// Set when the live input has real signal but nothing is resolving a
    /// confident note/chord from it for a sustained stretch — heavy
    /// distortion, noise, or (in Notes mode) a strummed chord the detector
    /// isn't meant to read. Cleared the instant a result locks in or the
    /// signal drops back to silence. See `trackSignalClarity`.
    var unclearSignalMessage: String?
    private var unclearSignalSince: ContinuousClock.Instant?
    /// Long enough that a pick attack's brief mistracking never trips this,
    /// short enough to still read as responsive.
    private static let unclearSignalHoldDuration = Duration.seconds(1)
    /// Same noise floor as `InputLevelPanel`'s meter — signal has to clear
    /// this before "no result" means anything; below it, there's simply
    /// nothing playing.
    private static let signalPresenceFloorDB: Double = -50
    private static func decibels(_ level: Float) -> Double { 20 * log10(max(Double(level), 0.000_001)) }
    private let audioEngine = AudioEngine()

#if DEBUG
    /// The sample-capture screen drives the recorder directly. It is a
    /// maintainer tool, so this is the one seam it gets rather than the
    /// recorder's state being folded into the ordinary UI state.
    var sampleRecorder: SampleRecorder { audioEngine.sampleRecorder }

    func setSampleRecordingEnabled(_ value: Bool) {
        audioEngine.setSampleRecordingEnabled(value)
    }
#endif
    private let resolver = FretPositionResolver()
    private var resolvedMIDI: Int?
    private let deviceWatcher = AudioDeviceWatcher()
    /// Coalesces a burst of `deviceWatcher.onChange` notifications (a
    /// multi-stream interface unplugging can fire several in quick
    /// succession) into one rescan, and keeps the scan itself off the main
    /// actor — see `scheduleDeviceRefresh`.
    private var pendingDeviceRefresh: Task<Void, Never>?
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
    private let practiceState = PracticeStateStore()

    init() {
        refreshDevices()
        audioEngine.onUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.publish(update)
            }
        }
        audioEngine.onChordUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.chordDisplay = update
                self.appendToHistory(update.chord)
                if self.detectionMode == .chords { self.trackSignalClarity(level: update.level, hasResult: update.chord != nil) }
            }
        }
        audioEngine.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.errorMessage = message
                self?.isReconnecting = false
            }
        }
        audioEngine.onRecovered = { [weak self] in
            Task { @MainActor [weak self] in
                self?.errorMessage = nil
                self?.isReconnecting = false
            }
        }
        audioEngine.onReconnecting = { [weak self] in
            Task { @MainActor [weak self] in
                self?.isReconnecting = true
            }
        }
        // Picks up hardware plugged in after launch — e.g. an interface
        // connected once the app is already running — without the user
        // having to notice and hit Rescan themselves.
        deviceWatcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleDeviceRefresh()
            }
        }
        let settings = practiceState.state.settings
        let restoredInput = restoreSelection(uid: settings.inputDeviceUID, legacyIDKey: "selectedInputDeviceID", from: inputDevices)
        selectedInputUID = restoredInput?.uid
        selectedInputDeviceID = restoredInput?.id ?? inputDevices.first?.id
        let restoredOutput = restoreSelection(uid: settings.outputDeviceUID, legacyIDKey: "selectedOutputDeviceID", from: outputDevices)
        selectedOutputUID = restoredOutput?.uid
        selectedOutputDeviceID = restoredOutput?.id ?? outputDevices.first?.id
        sensitivity = settings.sensitivity
        // Property observers do not fire for a value assigned inside the
        // type's own initialiser, so restoring `sensitivity` above never
        // reached `applySensitivity`. The slider showed the saved value while
        // the detector kept running at its 0.5 default until the user happened
        // to move it. Applying it explicitly here is what actually restores it.
        applySensitivity()
        // Persist whatever the restore resolved — which matters for the legacy
        // numeric-ID path, where the UID is only learned by looking at the
        // devices present. `update` writes nothing when nothing changed.
        let inputUID = selectedInputUID
        let outputUID = selectedOutputUID
        practiceState.update {
            $0.settings.inputDeviceUID = inputUID
            $0.settings.outputDeviceUID = outputUID
        }
    }

    /// Synchronous, on the main actor — fine for an explicit user action
    /// (launch, the Rescan button, "Refresh devices" in the error banner),
    /// which isn't the case this is trying to protect against. The
    /// automatic path triggered by device-change notifications goes through
    /// `scheduleDeviceRefresh` instead.
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
    private func restoreSelection(uid: String?, legacyIDKey: String, from devices: [AudioDevice]) -> AudioDevice? {
        if let uid, let match = devices.first(where: { $0.uid == uid }) {
            return match
        }
        if let legacy = practiceState.legacyDeviceID(forKey: legacyIDKey),
           let match = devices.first(where: { $0.id == legacy }) {
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
        let uid = inputDevices.first { $0.id == id }?.uid
        selectedInputUID = uid
        if uid != nil { practiceState.update { $0.settings.inputDeviceUID = uid } }
        start()
    }

    func selectOutputDevice(_ id: AudioDeviceID?) {
        selectedOutputDeviceID = id
        let uid = outputDevices.first { $0.id == id }?.uid
        selectedOutputUID = uid
        if uid != nil { practiceState.update { $0.settings.outputDeviceUID = uid } }
        start()
    }

    private func applyMonitorVolume() {
        audioEngine.setMonitorVolume(monitorMuted ? 0 : Float(monitorVolume))
    }

    private func applySensitivity() {
        let value = sensitivity
        audioEngine.setSensitivity(value)
        practiceState.update { $0.settings.sensitivity = value }
    }

    func start() {
        guard let selectedInputDeviceID, let selectedOutputDeviceID else { return }
        errorMessage = nil
        isReconnecting = false
        audioEngine.start(inputDeviceID: selectedInputDeviceID, outputDeviceID: selectedOutputDeviceID, monitorVolume: monitorMuted ? 0 : Float(monitorVolume))
    }

    func retryAudio() { start() }

    /// The analysis worker republishes the held note about thirty times a
    /// second, but only a genuine change of note is a new event to score —
    /// feeding it every frame would let one sustained note walk the resolver's
    /// hand-position estimate along the neck.
    /// Rate-limits the worker's stream to `displayInterval`, except when the
    /// note itself changes, or `detectRepick` catches the same note being hit
    /// again: both are events a player is waiting to see (the fretboard
    /// marker, the history strip), so they go through immediately and the
    /// clock restarts from there. Everything else — level, cents, frequency —
    /// is a value the eye reads, not an event it waits for, and can sit until
    /// the next refresh.
    ///
    /// Dropping the updates in between is safe because another always follows
    /// within ~33ms; nothing here is the only carrier of a state change.
    private func publish(_ update: PitchDisplayState) {
        // Tracked from the raw, un-throttled update rather than `display` —
        // the throttle below exists for redraw cost, not for how quickly a
        // "no clear pitch" hint should react to the signal actually
        // clearing or reappearing. The pitch worker keeps running
        // regardless of mode, so this only feeds the hint while Notes mode
        // is actually what's on screen — `onChordUpdate` does the same for
        // Chords mode.
        if detectionMode == .notes { trackSignalClarity(level: update.level, hasResult: update.note != nil) }
        let now = ContinuousClock.now
        let noteChanged = update.note?.midiNote != display.note?.midiNote
        // Checked ahead of the throttle below (and using update.level, not
        // display.level) so a repick is never missed to the 12Hz display
        // gate — a pick attack's level rise can be over well within 83ms.
        let isRepick = detectRepick(level: update.level, note: update.note)
        if !noteChanged, !isRepick, let lastPublish, now - lastPublish < Self.displayInterval { return }
        lastPublish = now
        var shown = update
        shown.latencyMilliseconds = stableLatency(update.latencyMilliseconds)
        display = shown
        resolvePositions(for: update.note, isRepick: isRepick)
    }

    /// A repick of the *same* pitch produces no midiNote change for
    /// `resolvePositions` to notice — so without this, hitting the exact
    /// same note twice in a row would only ever log the first hit. Mirrors
    /// `ChordAnalysisWorker`'s onset heuristic: a level jump to this
    /// multiple of the previous reading is a fresh pick attack, not the
    /// same note still ringing (which decays, it doesn't jump back up).
    /// Same ratio, same caveat — reasoned from the shape of a pluck's
    /// attack, not yet tuned against a real guitar.
    private static let noteOnsetRatio: Float = 1.6
    private var previousNoteLevel: Float = 0

    private func detectRepick(level: Float, note: MappedNote?) -> Bool {
        defer { previousNoteLevel = level }
        guard let note, note.midiNote == resolvedMIDI else { return false }
        return level > previousNoteLevel * Self.noteOnsetRatio
    }

    /// A player strumming a heavily distorted chord, a muted/percussive hit,
    /// or just room noise can hold real signal — above the meter's own noise
    /// floor — without either detector ever locking a result. Left silent,
    /// that reads as the app simply not working; this turns it into an
    /// actionable hint once it's been true long enough to be a pattern
    /// rather than one missed frame during an attack transient.
    private func trackSignalClarity(level: Float, hasResult: Bool) {
        guard Self.decibels(level) > Self.signalPresenceFloorDB, !hasResult else {
            unclearSignalSince = nil
            // Assigning `nil` over `nil` is still a mutation as far as
            // `@Observable` is concerned, and this runs on every published
            // frame — so writing unconditionally would invalidate every view
            // reading this property ~30 times a second to say nothing
            // changed. Same reason for the guarded writes below.
            if unclearSignalMessage != nil { unclearSignalMessage = nil }
            return
        }
        let now = ContinuousClock.now
        guard let since = unclearSignalSince else {
            unclearSignalSince = now
            return
        }
        if now - since >= Self.unclearSignalHoldDuration {
            let message = detectionMode == .chords
                ? "No clear chord detected. Try a cleaner strum with less noise or distortion."
                : "No clear pitch detected. Try a single clean note, less distortion, or raise sensitivity."
            if unclearSignalMessage != message { unclearSignalMessage = message }
        }
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
        let updated = Self.appending(match, to: chordHistory, limit: Self.chordHistoryLimit)
        // `appending` returns the list untouched while the same chord is
        // still ringing, which is most of the time — see `unclearSignalMessage`
        // above for why storing that unchanged value anyway is not free.
        // Count plus last id is enough to tell a real append apart from a
        // no-op: entries are only ever appended (and trimmed from the front),
        // so an append either grows the list or, at the cap, changes its last id.
        guard updated.count != chordHistory.count || updated.last?.id != chordHistory.last?.id else { return }
        chordHistory = updated
    }

    /// Also releases the pin — a pin referencing a now-gone entry would
    /// silently keep the fretboard frozen on a chord that no longer appears
    /// anywhere in the strip, which reads as the clear having partly failed.
    func clearChordHistory() {
        chordHistory = []
        pinnedChordHistoryID = nil
    }

    /// Also cancels any in-flight debounce (see `scheduleHistoryAppend`) —
    /// otherwise a pending append from just before the clear could land
    /// right after it and put one entry back.
    func clearNoteHistory() {
        pendingHistoryTask?.cancel()
        pendingHistoryTask = nil
        noteHistory = []
        pinnedNoteHistoryID = nil
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
        let updated = Self.appending(note, positions: positions, to: noteHistory, limit: Self.noteHistoryLimit)
        guard updated.count != noteHistory.count || updated.last?.id != noteHistory.last?.id else { return }
        noteHistory = updated
    }

    /// Debounces history logging against pitch-detector jitter around a
    /// pluck's attack transient, where the raw estimate can briefly swing
    /// through a wrong harmonic or an adjacent octave before settling on the
    /// true pitch. Each swing is a genuine midiNote change as far as
    /// `resolvePositions` is concerned, so without this a single pluck could
    /// log two or three history entries instead of one. Mirrors the settle
    /// window `ChordAnalysisWorker` already uses for the same reason on the
    /// chord side. Only the note still current after the window gets
    /// logged; the live fretboard/tuner readout is untouched by this and
    /// stays instant.
    private static let noteHistorySettle = Duration.milliseconds(90)
    private var pendingHistoryTask: Task<Void, Never>?

    private func scheduleHistoryAppend(_ note: MappedNote, positions: [RankedPosition]) {
        pendingHistoryTask?.cancel()
        let targetMIDI = note.midiNote
        pendingHistoryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.noteHistorySettle)
            guard !Task.isCancelled, let self, self.resolvedMIDI == targetMIDI else { return }
            self.appendToNoteHistory(note, positions: positions)
        }
    }

    /// Pure cap step, mirroring `appending(_:to:limit:)` for chords —
    /// deliberately *not* deduped against the last entry the way the chord
    /// version is. Chords have no onset detection reaching this layer, so
    /// their dedup is the only thing standing between a held chord and
    /// dozens of duplicate log lines. Notes are different: `resolvePositions`
    /// only ever calls this at a genuine pitch change or a detected repick
    /// (`detectRepick`'s onset check), both real events — including the
    /// case this exists to support, hitting the exact same note twice in a
    /// row, which a name-based dedup here would silently swallow.
    nonisolated static func appending(_ note: MappedNote?, positions: [RankedPosition], to history: [NoteHistoryEntry], limit: Int) -> [NoteHistoryEntry] {
        guard let note else { return history }
        var result = history + [NoteHistoryEntry(note: note, positions: positions)]
        if result.count > limit { result.removeFirst(result.count - limit) }
        return result
    }

    private func resolvePositions(for note: MappedNote?, isRepick: Bool = false) {
        guard let note else {
            fretPositions = []
            resolvedMIDI = nil
            pendingHistoryTask?.cancel()
            pendingHistoryTask = nil
            return
        }
        guard note.midiNote != resolvedMIDI else {
            // The pitch hasn't changed, so there's no new hand position to
            // resolve — but a repick of it is still a new history entry.
            // `fretPositions` is already correct for this pitch (it was set
            // the last time the note actually changed to it), so this only
            // needs to log again, not recompute anything.
            if isRepick { scheduleHistoryAppend(note, positions: fretPositions) }
            return
        }
        resolvedMIDI = note.midiNote
        fretPositions = resolver.resolve(midiNote: note.midiNote)
        scheduleHistoryAppend(note, positions: fretPositions)
    }

    // pendingDeviceRefresh is left to run out on its own at deinit — it
    // captures `self` weakly, so there's nothing for it to do once this
    // instance is gone, and Task.cancel() isn't safe to call from a
    // nonisolated deinit against a main-actor-isolated property.
    deinit { audioEngine.stop() }
}
