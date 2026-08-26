import Foundation

/// Drives a guided run through a sequence of steps: a four-beat count-in, then
/// one step per beat, at a tempo the player can change mid-run.
///
/// Ported from `../fretwork/src/lib/guided-session.ts`. The contract is kept
/// exactly, including the details that look incidental and are not:
///
/// - The count-in is four beats, emitted as beats 1 through 4, and the *first*
///   beat is published immediately on `start` rather than after a delay — so
///   pressing play gives feedback in the same frame.
/// - Tempo is one of five presets, and changing it mid-run **reschedules the
///   pending step at the new tempo** rather than letting the current interval
///   run out first. That is what makes the tempo buttons feel connected to what
///   is happening.
/// - Every scheduled callback carries the generation it was scheduled under and
///   does nothing if that no longer matches, so a stopped session emits no
///   further audio and no further state.
///
/// The clock is injectable for the same reason `NoteSequencer`'s is: against a
/// real clock, "cancelled" and "not fired yet" are indistinguishable.
final class GuidedSession<Step: Sendable>: @unchecked Sendable {
    enum Status: String, Sendable {
        case idle, countIn, playing
    }

    struct Snapshot: Sendable, Equatable {
        var status: Status = .idle
        /// 1...4 during the count-in, nil otherwise.
        var countInBeat: Int?
        /// Index into the sequence while playing, nil otherwise.
        var currentIndex: Int?
        var total: Int = 0
        var tempoBpm: Int = GuidedSession.defaultTempoBpm
        /// Whether reaching the end starts again from the beginning. Only the
        /// progression case uses it; a scale run plays once.
        var loop: Bool = false
    }

    static var defaultTempoBpm: Int { 80 }
    /// The web's presets. Not a continuous slider: five named speeds are easier
    /// to return to than a position on a track.
    static var tempoPresets: [Int] { [40, 60, 80, 100, 120] }
    static var countInBeats: Int { 4 }

    typealias Clock = NoteSequencer.Clock

    private let clock: Clock
    private let onState: (@Sendable (Snapshot) -> Void)?
    private let onStep: (@Sendable (Step, Int) -> Void)?

    private let lock = NSLock()
    private var state = Snapshot()
    private var sequence: [Step] = []
    private var generation = 0
    /// The work a pending beat would do. Held so a tempo change can reschedule
    /// it at the new interval instead of waiting out the old one.
    private var pendingAction: (@Sendable () -> Void)?
    /// How many beats each step lasts. A scale run is one note per beat; a
    /// chord progression usually holds each chord for a bar.
    private var stepBeats = 1
    /// Carried alongside `pendingAction` so a tempo change reschedules a
    /// multi-beat step at its full length rather than collapsing it to one beat.
    private var pendingBeats = 1
    /// Identifies the most recent `schedule` call.
    ///
    /// The web version cancels the outstanding `setTimeout` before setting a
    /// new one. `Clock` has no cancellation — a deliberate simplification, since
    /// it only ever has to schedule — so rescheduling instead invalidates the
    /// old work by bumping this. Without it, changing tempo mid-run left the
    /// original timer in flight *and* added a new one, so the step fired twice:
    /// once at the old interval and once at the new. The generation token does
    /// not catch this, because a tempo change is not a new run.
    private var scheduleToken = 0

    init(
        clock: Clock = NoteSequencer.DispatchClock(queue: DispatchQueue(label: "com.fretlight.guided-session", qos: .userInitiated)),
        onState: (@Sendable (Snapshot) -> Void)? = nil,
        onStep: (@Sendable (Step, Int) -> Void)? = nil
    ) {
        self.clock = clock
        self.onState = onState
        self.onStep = onStep
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    // MARK: - Control

    /// - Parameters:
    ///   - loop: start again from the first step on reaching the end, with no
    ///     second count-in.
    ///   - beatsPerStep: how long each step is held. Clamped to at least 1.
    func start(_ steps: [Step], loop: Bool = false, beatsPerStep: Int = 1) {
        stop()
        guard !steps.isEmpty else { return }

        lock.lock()
        sequence = steps
        stepBeats = max(beatsPerStep, 1)
        state.status = .countIn
        state.countInBeat = 1
        state.currentIndex = nil
        state.total = steps.count
        state.loop = loop
        let run = generation
        let published = state
        lock.unlock()

        onState?(published)
        schedule(run: run) { [weak self] in self?.countIn(run: run, beat: 2) }
    }

    /// Total cancellation: no further steps, no further state, including from
    /// work already scheduled.
    func stop() {
        lock.lock()
        generation += 1
        pendingAction = nil
        pendingBeats = 1
        stepBeats = 1
        // Invalidates any timer still in flight, the same way a reschedule does.
        scheduleToken += 1
        sequence = []
        let wasRunning = state.status != .idle || state.total != 0
        if wasRunning {
            state = Snapshot(tempoBpm: state.tempoBpm)
        }
        let published = state
        lock.unlock()

        // Tempo survives a stop — it is the player's setting, not the run's.
        if wasRunning { onState?(published) }
    }

    @discardableResult func slower() -> Int { changeTempo(by: -1) }
    @discardableResult func faster() -> Int { changeTempo(by: 1) }

    @discardableResult
    func setTempo(_ bpm: Int) -> Int {
        let target = Self.tempoPresets.contains(bpm) ? bpm : Self.defaultTempoBpm
        return applyTempo(target)
    }

    private func changeTempo(by delta: Int) -> Int {
        lock.lock()
        let current = state.tempoBpm
        lock.unlock()
        let base = Self.tempoPresets.firstIndex(of: current)
            ?? Self.tempoPresets.firstIndex(of: Self.defaultTempoBpm)!
        let next = min(max(base + delta, 0), Self.tempoPresets.count - 1)
        return applyTempo(Self.tempoPresets[next])
    }

    private func applyTempo(_ bpm: Int) -> Int {
        lock.lock()
        guard bpm != state.tempoBpm else {
            lock.unlock()
            return bpm
        }
        state.tempoBpm = bpm
        let published = state
        let action = pendingAction
        let beats = pendingBeats
        let run = generation
        lock.unlock()

        onState?(published)
        // Reschedule what was already pending at the new tempo, at its own
        // length. Without this a tempo change would not be heard until the
        // current beat elapsed.
        if let action { schedule(run: run, beats: beats, action) }
        return bpm
    }

    // MARK: - The run

    private func schedule(run: Int, beats: Int = 1, _ work: @escaping @Sendable () -> Void) {
        lock.lock()
        pendingAction = work
        pendingBeats = beats
        scheduleToken += 1
        let token = scheduleToken
        let seconds = 60.0 / Double(state.tempoBpm) * Double(beats)
        lock.unlock()

        clock.schedule(after: seconds) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            // Stale either because the run was cancelled, or because this
            // timer was superseded by a reschedule at a new tempo.
            let stale = run != self.generation || token != self.scheduleToken
            if !stale {
                self.pendingAction = nil
                self.pendingBeats = 1
            }
            self.lock.unlock()
            guard !stale else { return }
            work()
        }
    }

    private func countIn(run: Int, beat: Int) {
        lock.lock()
        guard run == generation else { return lock.unlock() }
        state.status = .countIn
        state.countInBeat = beat
        state.currentIndex = nil
        let published = state
        lock.unlock()

        onState?(published)
        schedule(run: run) { [weak self] in
            guard let self else { return }
            if beat < Self.countInBeats {
                self.countIn(run: run, beat: beat + 1)
            } else {
                self.playStep(run: run, index: 0)
            }
        }
    }

    private func playStep(run: Int, index: Int) {
        lock.lock()
        guard run == generation else { return lock.unlock() }
        guard index < sequence.count else {
            let looping = state.loop && !sequence.isEmpty
            lock.unlock()
            // Looping restarts immediately, with no second count-in: the pulse
            // is already established by the time the first pass ends.
            if looping { playStep(run: run, index: 0) } else { finish(run: run) }
            return
        }
        let step = sequence[index]
        let beats = stepBeats
        state.status = .playing
        state.countInBeat = nil
        state.currentIndex = index
        let published = state
        lock.unlock()

        onState?(published)
        onStep?(step, index)
        schedule(run: run, beats: beats) { [weak self] in self?.playStep(run: run, index: index + 1) }
    }

    private func finish(run: Int) {
        lock.lock()
        guard run == generation else { return lock.unlock() }
        sequence = []
        pendingAction = nil
        state = Snapshot(tempoBpm: state.tempoBpm)
        let published = state
        lock.unlock()

        onState?(published)
    }
}

/// A chord progression run: the same engine, stepping over positions in a
/// progression rather than notes in a scale.
///
/// The web keeps `guided-session.ts` and `progression-session.ts` as separate
/// files with near-identical bodies. They differ only in that a progression can
/// loop and can hold each step for more than one beat, so here they are one
/// engine with those two parameters — one implementation of count-in, tempo
/// rescheduling and generation-token cancellation to keep correct, instead of
/// two that must be kept identical by hand.
typealias ProgressionSession = GuidedSession<Int>

extension GuidedSession where Step == Int {
    /// Steps a progression of `total` chords, handing back each index.
    /// Mirrors the web's `start(total, loop, beatsPerStep)`.
    func startProgression(total: Int, loop: Bool, beatsPerStep: Int = 1) {
        guard total >= 1 else {
            stop()
            return
        }
        start(Array(0..<total), loop: loop, beatsPerStep: beatsPerStep)
    }
}
