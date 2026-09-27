import Foundation
import Observation

@MainActor @Observable
final class AppState {
    /// The platform audio seam. Internal so Mac-only surfaces (see
    /// `AppState+Mac`) and tests can cast it back to the concrete controller.
    let audio: any AudioControlling
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
            updateDetectionGating()
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
    /// Purely a display orientation for every board in the app — doesn't touch
    /// the pitch pipeline or `GuitarTuning`'s string indices, just which row
    /// `BoardGeometry` draws each index at.
    ///
    /// Persisted, unlike `detectionMode`. It was a per-session flag that reset
    /// on every launch, which meant a player who prefers the player's-eye view
    /// re-flipped it every time; with a board on ten module screens it has to
    /// be one preference applied everywhere.
    ///
    /// False is the default board: Low E along the bottom, High E on top —
    /// tablature's convention (pitch rises up the page), and the same
    /// orientation the web app draws, so a shape looks identical in both.
    /// The tuning every board in the app draws, and the one sample playback
    /// pitches against. Global rather than per-screen: an instrument has one
    /// tuning at a time, and a shape shown in Drop D on one screen and standard
    /// on the next would be teaching two different instruments.
    ///
    /// Persisted. The document has carried `tuningID` since workstream 001, but
    /// until now nothing read it back — the field was written and never used.
    var tuning: Tuning = Tunings.standard {
        didSet {
            guard tuning != oldValue else { return }
            let id = tuning.id
            practiceState.update { $0.settings.tuningID = id }
        }
    }

    var isFretboardFlipped = false {
        didSet {
            guard isFretboardFlipped != oldValue else { return }
            practiceState.update { $0.settings.isFretboardFlipped = isFretboardFlipped }
        }
    }

    /// An opt-in compact pitch readout for learning modules. The pitch worker
    /// already runs for the app's audio graph; this only changes whether its
    /// result is visible outside Listen.
    var showsLiveNoteOnModules = false {
        didSet {
            guard showsLiveNoteOnModules != oldValue else { return }
            practiceState.update { $0.settings.showsLiveNoteOnModules = showsLiveNoteOnModules }
        }
    }

    /// A second, independently persisted choice for players who want live
    /// feedback to reach the fretboard as well as the compact header readout.
    /// It takes effect only while that header readout is visible; keeping the
    /// preference when the header is temporarily off avoids making a player
    /// configure the same practice aid twice.
    var highlightsLiveNoteOnFretboards = false {
        didSet {
            guard highlightsLiveNoteOnFretboards != oldValue else { return }
            practiceState.update { $0.settings.highlightsLiveNoteOnFretboards = highlightsLiveNoteOnFretboards }
        }
    }

    /// A separate, explicit preference: this sends one anonymous activity
    /// pulse per UTC day. It does not alter audio capture or any feature.
    var sharesAnonymousUsageData = false {
        didSet {
            guard sharesAnonymousUsageData != oldValue else { return }
            practiceState.update { $0.settings.sharesAnonymousUsageData = sharesAnonymousUsageData }
            usageTelemetry.recordActiveDayIfEnabled(sharesAnonymousUsageData)
        }
    }

    /// Detection costs CPU only while something is looking at it. Screens that
    /// show no live readout leave the workers idle, using the gate
    /// `ChordAnalysisWorker` already has — an idle worker costs one `write` per
    /// render block rather than a running detector.
    ///
    /// Deliberately *not* a graph rebuild: gating must never reach
    /// `startSynchronously`, which renegotiates the device and feeds the
    /// debounced restart path. It only flips a flag the workers already read.
    private func updateDetectionGating() {
        let wanted = selectedScreen.needsDetection && detectionMode == .chords
        isChordDetectionActive = wanted
        audio.setChordDetectionEnabled(wanted)
    }

    /// Mirrors what was last handed to the engine. Exists so the gate can be
    /// asserted without reaching into the audio controller's own queue, where
    /// reading the flag would race the write.
    private(set) var isChordDetectionActive = false

    var isChordDetectionActiveForTesting: Bool { isChordDetectionActive }
    var persistedFretboardFlipForTesting: Bool { practiceState.state.settings.isFretboardFlipped }
    var persistedLiveNoteVisibilityForTesting: Bool { practiceState.state.settings.showsLiveNoteOnModules }
    var persistedLiveNoteHighlightForTesting: Bool { practiceState.state.settings.highlightsLiveNoteOnFretboards }
    /// Where the current note is most likely being played, best candidate
    /// first. Derived here rather than on the analysis thread because it
    /// depends on playing history, not on the audio.
    private(set) var fretPositions: [RankedPosition] = []
    var errorMessage: String?
    /// True from the moment the audio controller starts an automatic recovery
    /// attempt until it either succeeds (`.recovered`) or gives up
    /// (`.error`). Distinct from `errorMessage`: that only appears once
    /// recovery has been exhausted, which otherwise leaves the UI showing
    /// nothing — audio dead, meter silent, no explanation — for the whole
    /// multi-second retry window. Surfacing this instead is what turns that
    /// window from "looks frozen" into "visibly reconnecting".
    var isReconnecting = false
    /// Whether the audio graph has ever come up in this session.
    ///
    /// The build watchdog reports a slow *first* build through the same
    /// `onReconnecting` callback a mid-session device drop uses, and on a first
    /// build there is nothing to reconnect to — so without this the app told a
    /// player with a slow-binding interface that it was "Reconnecting to audio
    /// device" the first time they ever opened it. The two states also deserve
    /// different weight on screen: see `ListenScreen`.
    private(set) var hasStartedAudio = false
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
    private let usageTelemetry = UsageTelemetry()
    /// Which screen the shell is showing. Plain view state that happens to
    /// live on the one `@Observable` owner, per `CLAUDE.md` — not persisted:
    /// the web app deliberately always opens on home rather than restoring the
    /// last module, and reopening on a screen the player has forgotten they
    /// left open is worse than a consistent starting point.
    var selectedScreen: AppScreen = .listen {
        didSet {
            guard selectedScreen != oldValue else { return }
            updateDetectionGating()
            prepareSamplePlaybackIfNeeded()
        }
    }

    /// True once a note played from a module would actually be heard.
    private(set) var isSamplePlaybackReady = false
    /// Set if the bundled library could not be decoded — a shipped-resource
    /// failure, so it is worth surfacing rather than swallowing.
    private(set) var samplePlaybackError: String?
    private var hasRequestedSamplePlayback = false

    /// Decodes the note library the first time a screen that plays notes is
    /// opened.
    ///
    /// Deliberately lazy rather than done at launch: the decoded library is
    /// 85 MB, and someone who only ever uses the listening screen should not
    /// pay for it. Deliberately *not* left to the caller either — that was the
    /// bug. Every module called `playSample` on every tap while the library had
    /// never been asked for, so nothing sounded and nothing said why.
    private func prepareSamplePlaybackIfNeeded() {
        guard case .module = selectedScreen, !hasRequestedSamplePlayback else { return }
        hasRequestedSamplePlayback = true
        audio.prepareSamplePlayback { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.samplePlaybackError = error
                self.isSamplePlaybackReady = self.audio.isSamplePlaybackReady
                if error != nil { self.hasRequestedSamplePlayback = false }
            }
        }
    }

    var isSampleLibraryLoadedForTesting: Bool { audio.isSampleLibraryLoaded }

    /// Re-checked when a module asks, because a graph rebuild between then and
    /// now replaces the player.
    func refreshSamplePlaybackReadiness() {
        prepareSamplePlaybackIfNeeded()
        isSamplePlaybackReady = audio.isSamplePlaybackReady
    }

    private let resolver = FretPositionResolver()
    private var resolvedMIDI: Int?
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
    private let practiceState: PracticeStateStore

    /// - Parameters:
    ///   - audio: the platform implementation of the shared seam.
    ///   - store: the persisted document. **Must be the same instance the
    ///     audio controller was built with**, or their two views of the device
    ///     selection diverge: `MacAudioController` writes the resolved
    ///     device UIDs into the store it holds, and `AppState` reads and writes
    ///     sensitivity, tuning and the other preferences through its own
    ///     reference. `AppState()` (see `AppState+Mac`) constructs one store
    ///     and passes it to both.
    init(audio: any AudioControlling, store: PracticeStateStore = PracticeStateStore()) {
        self.audio = audio
        self.practiceState = store
        // Subscribed before anything can call `start()`: the controller's own
        // callbacks are already installed, and `start()` is only reached from
        // the UI, after this returns. The controller delivers on the main
        // actor (see `AudioControlling`), and the closure is `@MainActor`, so
        // this is a direct call — no extra `Task` past the one the engine
        // callback already made.
        audio.onEvent = { [weak self] event in
            self?.handle(event)
        }
        let settings = store.state.settings
        sensitivity = settings.sensitivity
        // Restored the same way, and safe to assign directly: this one's
        // `didSet` only writes the value back, so a missed observer costs
        // nothing. `sensitivity` below is the opposite case.
        isFretboardFlipped = settings.isFretboardFlipped
        showsLiveNoteOnModules = settings.showsLiveNoteOnModules
        highlightsLiveNoteOnFretboards = settings.highlightsLiveNoteOnFretboards
        sharesAnonymousUsageData = settings.sharesAnonymousUsageData
        tuning = Tunings.tuning(id: settings.tuningID)
        // Property observers do not fire for a value assigned inside the
        // type's own initialiser, so restoring `sensitivity` above never
        // reached `applySensitivity`. The slider showed the saved value while
        // the detector kept running at its 0.5 default until the user happened
        // to move it. Applying it explicitly here is what actually restores it.
        applySensitivity()
        // Property observers do not run for assignments during `init`, so an
        // existing opt-in needs its one daily pulse requested explicitly.
        usageTelemetry.recordActiveDayIfEnabled(sharesAnonymousUsageData)
    }

    /// Builds the Notes module's model, wired to this app's persisted state and
    /// to sample playback in the current tuning.
    ///
    /// A factory because it captures `self`, which a stored property cannot
    /// do during initialisation.
    func makeNotesModuleModel() -> NotesModuleModel {
        NotesModuleModel(
            tuning: tuning,
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(
                    string: position.string,
                    fret: position.fret,
                    tuning: self.tuning
                )
            }
        )
    }

    /// Builds the Intervals module's model, wired the same way as Notes.
    func makeIntervalsModuleModel() -> IntervalsModuleModel {
        IntervalsModuleModel(
            tuning: tuning,
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makeOctavesModuleModel() -> OctavesModuleModel {
        OctavesModuleModel(
            tuning: tuning,
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makeTriadsModuleModel() -> TriadsModuleModel {
        TriadsModuleModel(
            tuning: tuning,
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makeChordsModuleModel() -> ChordsModuleModel {
        ChordsModuleModel(
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makePentatonicModuleModel() -> PentatonicModuleModel {
        PentatonicModuleModel(
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makeScalesModuleModel() -> ScalesModuleModel {
        ScalesModuleModel(
            tuning: tuning,
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makeHarmonizingModuleModel() -> HarmonizingModuleModel {
        HarmonizingModuleModel(
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makeCircleModuleModel() -> CircleModuleModel {
        CircleModuleModel(
            tuning: tuning,
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    func makeNoteAssociationModuleModel() -> NoteAssociationModuleModel {
        NoteAssociationModuleModel(
            tuning: tuning,
            store: practiceState,
            play: { [weak self] position in
                guard let self else { return }
                self.audio.playSample(string: position.string, fret: position.fret, tuning: self.tuning)
            }
        )
    }

    private func applySensitivity() {
        let value = sensitivity
        audio.setSensitivity(value)
        practiceState.update { $0.settings.sensitivity = value }
    }

    func start() {
        // Clear the banner only when a start was actually issued. `start()` on
        // a controller with no device selected must not wipe the error message
        // that explains why — Retry used to blank it in that case.
        guard audio.start() else { return }
        errorMessage = nil
        isReconnecting = false
    }

    func retryAudio() { start() }

    /// Dispatches one event from the audio seam. The bodies are the verbatim
    /// five engine callbacks `AppState` used to install directly.
    private func handle(_ event: AudioControllerEvent) {
        switch event {
        case .noteUpdate(let update):
            publish(update)
        case .chordUpdate(let update):
            chordDisplay = update
            appendToHistory(update.chord)
            if detectionMode == .chords { trackSignalClarity(level: update.level, hasResult: update.chord != nil) }
        case .error(let message):
            errorMessage = message
            isReconnecting = false
        case .recovered:
            errorMessage = nil
            isReconnecting = false
            hasStartedAudio = true
        case .reconnecting:
            isReconnecting = true
        }
    }

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

    isolated deinit { audio.stop() }
}
