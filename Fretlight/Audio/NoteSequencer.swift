import Foundation

/// Plays a run of positions with a gap between them, optionally finishing on a
/// strum, and cancels totally.
///
/// Ported from the web app's `playSequence`/`strum` in `src/lib/audio.ts`. The
/// synthesised voice went away with workstream 002; the musical behaviour built
/// on top did not, and each piece of it was a considered choice there:
///
/// - one note is scheduled at a time rather than committing a whole run to a
///   timeline, so a run stays cancellable and a new sequence cannot start
///   before a previous future event has cleared
/// - a strum is a sequence of notes a few milliseconds apart, not a chord
/// - a few cents of random detune per note keeps repeats and strums from
///   sounding identical
///
/// The detune matters more here than it did there. The web app synthesised
/// every note fresh; this one has exactly one recording per position and no
/// round-robin, so without variation a repeated note is bit-identical and reads
/// as a machine rather than a instrument.
final class NoteSequencer: @unchecked Sendable {
    /// Where the work is scheduled. Injectable so tests can drive a sequence
    /// frame by frame instead of sleeping through it — cancellation is the
    /// property most worth testing here and the hardest to test against a real
    /// clock.
    protocol Clock: Sendable {
        func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void)
    }

    struct DispatchClock: Clock {
        let queue: DispatchQueue
        func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
            if delay <= 0 {
                queue.async(execute: work)
            } else {
                queue.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }
    }

    struct Options: Sendable {
        /// Seconds between notes. The web app's default.
        var gap: TimeInterval = 0.55
        /// Finish by sounding every note together.
        var strumTogether = false
        /// Fired as each note sounds, so the UI can pulse that dot. `index` is
        /// the note's place in the run, or -1 for a note that is part of the
        /// closing strum — matching the web contract exactly.
        var onHit: (@Sendable (FretPosition, Int) -> Void)?
        var onComplete: (@Sendable () -> Void)?
    }

    /// Inter-note offset inside a sequence's closing strum.
    static let sequenceStrumOffset: TimeInterval = 0.025
    /// Inter-note offset for a standalone `strum`. Slightly wider than the
    /// above, as in the web app.
    static let strumOffset: TimeInterval = 0.030
    /// Pause between the last sequenced note and the closing strum.
    static let beforeStrum: TimeInterval = 0.150
    /// Random detune per note, in cents either side of true pitch.
    static let detuneCents = 2.5
    /// Random level variation per note, either side of nominal. Small: this is
    /// pick-force variation, not dynamics.
    static let gainJitter: Float = 0.06

    private let play: @Sendable (FretPosition, Double, Float) -> Void
    private let clock: Clock
    private let lock = NSLock()
    /// Bumped by every `stop` and every new sequence. Work already in flight
    /// carries the generation it was scheduled under and does nothing if it no
    /// longer matches — the pattern the web app's `guided-session.ts` uses,
    /// which is already proven against exactly this class of bug.
    private var generation = 0

    /// - Parameter play: sounds one position at a pitch ratio and gain.
    ///   Deliberately a closure rather than a `SamplePlayer`, so a sequence can
    ///   be tested without an audio graph.
    init(
        clock: Clock = DispatchClock(queue: DispatchQueue(label: "com.fretlight.sequencer", qos: .userInitiated)),
        play: @escaping @Sendable (FretPosition, Double, Float) -> Void
    ) {
        self.clock = clock
        self.play = play
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func beginGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    /// Cancellation is total: after this returns, no further audio and no
    /// further callbacks, including from work already scheduled.
    func stop() {
        _ = beginGeneration()
    }

    /// Sounds one position now, with the per-note variation every note gets.
    func pluck(_ position: FretPosition) {
        play(position, Self.randomDetuneRatio(), Self.randomGain())
    }

    /// Plays `positions` in order. Returns immediately; the run proceeds on the
    /// clock. Starting a new run cancels any run already in progress, for the
    /// same reason `stop` exists.
    func play(_ positions: [FretPosition], options: Options = Options()) {
        guard !positions.isEmpty else {
            options.onComplete?()
            return
        }
        let generation = beginGeneration()
        step(positions, index: 0, options: options, generation: generation)
    }

    private func step(_ positions: [FretPosition], index: Int, options: Options, generation: Int) {
        guard currentGeneration() == generation else { return }

        guard index < positions.count else {
            if options.strumTogether, positions.count > 1 {
                clock.schedule(after: Self.beforeStrum) { [weak self] in
                    self?.runStrum(positions, offset: Self.sequenceStrumOffset, options: options, generation: generation)
                }
            } else {
                options.onComplete?()
            }
            return
        }

        let position = positions[index]
        pluck(position)
        options.onHit?(position, index)

        clock.schedule(after: options.gap) { [weak self] in
            self?.step(positions, index: index + 1, options: options, generation: generation)
        }
    }

    /// Sounds every position with a small offset between them, as a hand
    /// crossing the strings does.
    func strum(_ positions: [FretPosition], onComplete: (@Sendable () -> Void)? = nil) {
        guard !positions.isEmpty else {
            onComplete?()
            return
        }
        var options = Options()
        options.onComplete = onComplete
        let generation = beginGeneration()
        runStrum(positions, offset: Self.strumOffset, options: options, generation: generation)
    }

    private func runStrum(_ positions: [FretPosition], offset: TimeInterval, options: Options, generation: Int) {
        for (index, position) in positions.enumerated() {
            clock.schedule(after: offset * Double(index)) { [weak self] in
                guard let self, self.currentGeneration() == generation else { return }
                self.pluck(position)
                // -1: part of a strum rather than a place in the run. The web
                // contract, kept so a ported caller reads the same.
                options.onHit?(position, -1)
                if index == positions.count - 1 { options.onComplete?() }
            }
        }
    }

    // MARK: - Per-note variation

    /// ±2.5 cents as a frequency ratio, which is what the player's
    /// `rateMultiplier` takes.
    static func randomDetuneRatio() -> Double {
        let cents = Double.random(in: -detuneCents...detuneCents)
        return pow(2, cents / 1200)
    }

    static func randomGain() -> Float {
        1 - Float.random(in: 0...gainJitter)
    }
}
