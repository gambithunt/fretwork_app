import XCTest
@testable import Fretwork

/// A clock the test drives by hand. Cancellation is the property most worth
/// testing here and the hardest to test against a real one: a sequence that
/// "stopped" but still had a timer in flight would pass any test that simply
/// waited long enough and then stopped looking.
private final class ManualClock: NoteSequencer.Clock, @unchecked Sendable {
    /// Identified by a serial number rather than by the closure itself.
    /// Closures have no identity in Swift — boxing one with `as AnyObject`
    /// produces a *new* box each time, so matching on it never finds anything
    /// and every scheduled item is silently skipped.
    private struct Item {
        let id: Int
        let due: TimeInterval
        let work: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var pending: [Item] = []
    private var nextID = 0
    private(set) var now: TimeInterval = 0

    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        lock.lock()
        pending.append(Item(id: nextID, due: now + delay, work: work))
        nextID += 1
        lock.unlock()
    }

    /// Runs everything due at or before `now + interval`, in time order,
    /// including work scheduled by that work. Ties break on scheduling order,
    /// so a strum's notes fire in the order they were queued.
    func advance(by interval: TimeInterval) {
        let target = now + interval
        while true {
            lock.lock()
            let due = pending.filter { $0.due <= target }
            guard let next = due.min(by: { ($0.due, $0.id) < ($1.due, $1.id) }),
                  let index = pending.firstIndex(where: { $0.id == next.id })
            else {
                lock.unlock()
                break
            }
            pending.remove(at: index)
            now = max(now, next.due)
            lock.unlock()
            next.work()
        }
        lock.lock()
        now = target
        lock.unlock()
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var played: [FretPosition] = []
    private(set) var rates: [Double] = []
    private(set) var gains: [Float] = []
    private(set) var hits: [(FretPosition, Int)] = []
    private(set) var completions = 0

    func play(_ position: FretPosition, _ rate: Double, _ gain: Float) {
        lock.lock()
        played.append(position)
        rates.append(rate)
        gains.append(gain)
        lock.unlock()
    }

    func hit(_ position: FretPosition, _ index: Int) {
        lock.lock()
        hits.append((position, index))
        lock.unlock()
    }

    func complete() {
        lock.lock()
        completions += 1
        lock.unlock()
    }
}

final class NoteSequencerTests: XCTestCase {
    private func makeSequencer() -> (NoteSequencer, ManualClock, Recorder) {
        let clock = ManualClock()
        let recorder = Recorder()
        let sequencer = NoteSequencer(clock: clock) { position, rate, gain in
            recorder.play(position, rate, gain)
        }
        return (sequencer, clock, recorder)
    }

    private let run = [
        FretPosition(string: 0, fret: 0),
        FretPosition(string: 1, fret: 2),
        FretPosition(string: 2, fret: 4)
    ]

    // MARK: - Sequencing

    func testTheFirstNoteSoundsImmediatelyAndTheRestOnTheGap() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.gap = 0.5
        options.onHit = { position, index in recorder.hit(position, index) }
        options.onComplete = { recorder.complete() }

        sequencer.play(run, options: options)
        XCTAssertEqual(recorder.played, [run[0]], "the run starts without waiting for the first gap")

        clock.advance(by: 0.5)
        XCTAssertEqual(recorder.played, [run[0], run[1]])
        clock.advance(by: 0.5)
        XCTAssertEqual(recorder.played, run)
        XCTAssertEqual(recorder.completions, 0, "completion waits for the final gap to elapse")
        clock.advance(by: 0.5)
        XCTAssertEqual(recorder.completions, 1)
    }

    func testHitsCarryTheirIndexInTheRun() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.gap = 0.1
        options.onHit = { position, index in recorder.hit(position, index) }
        sequencer.play(run, options: options)
        clock.advance(by: 1)

        XCTAssertEqual(recorder.hits.map(\.1), [0, 1, 2])
        XCTAssertEqual(recorder.hits.map(\.0), run)
    }

    func testAnEmptyRunCompletesWithoutSoundingAnything() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.onComplete = { recorder.complete() }
        sequencer.play([], options: options)
        clock.advance(by: 5)
        XCTAssertEqual(recorder.played, [])
        XCTAssertEqual(recorder.completions, 1)
    }

    // MARK: - Strum

    func testASequenceCanFinishOnAStrum() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.gap = 0.1
        options.strumTogether = true
        options.onHit = { position, index in recorder.hit(position, index) }
        options.onComplete = { recorder.complete() }

        sequencer.play(run, options: options)
        clock.advance(by: 5)

        // Three sequenced notes, then all three again as the strum.
        XCTAssertEqual(recorder.played.count, 6)
        XCTAssertEqual(Array(recorder.played.suffix(3)), run)
        // The strum's hits are marked -1 rather than carrying a run index.
        XCTAssertEqual(recorder.hits.map(\.1), [0, 1, 2, -1, -1, -1])
        XCTAssertEqual(recorder.completions, 1)
    }

    func testAStandaloneStrumSoundsEveryNoteInOrder() {
        let (sequencer, clock, recorder) = makeSequencer()
        sequencer.strum(run) { recorder.complete() }

        // The first note lands at offset zero; the others are spaced out.
        XCTAssertEqual(recorder.played, [])
        clock.advance(by: 0)
        XCTAssertEqual(recorder.played, [run[0]])
        clock.advance(by: NoteSequencer.strumOffset)
        XCTAssertEqual(recorder.played, [run[0], run[1]])
        clock.advance(by: NoteSequencer.strumOffset)
        XCTAssertEqual(recorder.played, run)
        XCTAssertEqual(recorder.completions, 1)
    }

    // MARK: - Cancellation

    func testAStoppedSequenceEmitsNothingFurther() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.gap = 0.1
        options.onHit = { position, index in recorder.hit(position, index) }
        options.onComplete = { recorder.complete() }

        sequencer.play(run, options: options)
        XCTAssertEqual(recorder.played.count, 1)

        sequencer.stop()
        // Work for the rest of the run is still scheduled — this is exactly the
        // case a real clock hides, because the timer fires whether or not the
        // sequence is still wanted.
        XCTAssertGreaterThan(clock.pendingCount, 0)
        clock.advance(by: 10)

        XCTAssertEqual(recorder.played.count, 1, "no further audio after stop")
        XCTAssertEqual(recorder.hits.count, 1, "no further callbacks after stop")
        XCTAssertEqual(recorder.completions, 0, "a stopped run does not complete")
    }

    func testStoppingDuringTheStrumSilencesTheRest() {
        let (sequencer, clock, recorder) = makeSequencer()
        sequencer.strum(run) { recorder.complete() }
        clock.advance(by: 0)
        XCTAssertEqual(recorder.played.count, 1)

        sequencer.stop()
        clock.advance(by: 10)
        XCTAssertEqual(recorder.played.count, 1)
        XCTAssertEqual(recorder.completions, 0)
    }

    /// Starting a run cancels the one before it. Without this, two overlapping
    /// sequences interleave and the caller has no way to tell whose callback
    /// is whose.
    func testANewRunCancelsTheOneInProgress() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.gap = 0.1
        options.onComplete = { recorder.complete() }

        sequencer.play(run, options: options)
        let second = [FretPosition(string: 5, fret: 7)]
        sequencer.play(second, options: options)
        clock.advance(by: 10)

        // One note from the abandoned run, then the whole of the new one.
        XCTAssertEqual(recorder.played, [run[0], second[0]])
        XCTAssertEqual(recorder.completions, 1, "only the surviving run completes")
    }

    func testRapidStartStopCyclesLeaveNothingRunning() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.gap = 0.05
        options.onComplete = { recorder.complete() }

        for _ in 0..<50 {
            sequencer.play(run, options: options)
            sequencer.stop()
        }
        clock.advance(by: 60)

        XCTAssertEqual(recorder.played.count, 50, "one note per start, and nothing after each stop")
        XCTAssertEqual(recorder.completions, 0)
        XCTAssertEqual(clock.pendingCount, 0, "no work left scheduled")
    }

    // MARK: - Per-note variation

    /// One recording per position and no round-robin, so without this a
    /// repeated note is bit-identical.
    func testEveryNoteGetsItsOwnDetuneAndLevel() {
        let (sequencer, clock, recorder) = makeSequencer()
        var options = NoteSequencer.Options()
        options.gap = 0.01
        let repeated = Array(repeating: FretPosition(string: 0, fret: 5), count: 30)
        sequencer.play(repeated, options: options)
        clock.advance(by: 5)

        XCTAssertEqual(recorder.rates.count, 30)
        XCTAssertGreaterThan(Set(recorder.rates).count, 20, "notes must not all share one detune")
        XCTAssertGreaterThan(Set(recorder.gains).count, 20, "notes must not all share one level")
    }

    /// ±2.5 cents. Wide enough to stop repeats sounding identical, narrow
    /// enough that nothing sounds out of tune.
    func testDetuneStaysWithinTwoAndAHalfCents() {
        for _ in 0..<500 {
            let ratio = NoteSequencer.randomDetuneRatio()
            let cents = 1200 * log2(ratio)
            XCTAssertLessThanOrEqual(abs(cents), NoteSequencer.detuneCents + 0.0001)
        }
    }

    func testGainJitterOnlyEverReducesLevel() {
        for _ in 0..<500 {
            let gain = NoteSequencer.randomGain()
            XCTAssertLessThanOrEqual(gain, 1, "jitter must not push a normalised sample into clipping")
            XCTAssertGreaterThanOrEqual(gain, 1 - NoteSequencer.gainJitter)
        }
    }
}
