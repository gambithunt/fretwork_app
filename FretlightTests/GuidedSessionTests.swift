import XCTest
@testable import Fretwork

/// Ported from the web app's `guided-session` and `progression-session`
/// behaviour. Driven by a hand-run clock, because against a real one
/// "cancelled" and "not fired yet" look the same.
private final class ManualClock: NoteSequencer.Clock, @unchecked Sendable {
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

    func advance(by interval: TimeInterval) {
        let target = now + interval
        while true {
            lock.lock()
            guard let next = pending.filter({ $0.due <= target }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }),
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
    private(set) var steps: [(step: String, index: Int)] = []
    private(set) var states: [GuidedSession<String>.Snapshot] = []

    func step(_ value: String, _ index: Int) {
        lock.lock(); steps.append((value, index)); lock.unlock()
    }

    func state(_ snapshot: GuidedSession<String>.Snapshot) {
        lock.lock(); states.append(snapshot); lock.unlock()
    }
}

final class GuidedSessionTests: XCTestCase {
    private let run = ["A", "B", "C"]
    /// One beat at the default 80bpm.
    private let beat = 60.0 / 80.0

    private func makeSession() -> (GuidedSession<String>, ManualClock, Recorder) {
        let clock = ManualClock()
        let recorder = Recorder()
        let session = GuidedSession<String>(
            clock: clock,
            onState: { recorder.state($0) },
            onStep: { recorder.step($0, $1) }
        )
        return (session, clock, recorder)
    }

    // MARK: - Count-in

    /// The first beat is published immediately, not after a delay: pressing
    /// play has to give feedback in the same frame.
    func testTheCountInStartsImmediatelyAtBeatOne() {
        let (session, _, recorder) = makeSession()
        session.start(run)

        XCTAssertEqual(session.snapshot.status, .countIn)
        XCTAssertEqual(session.snapshot.countInBeat, 1)
        XCTAssertEqual(session.snapshot.total, 3)
        XCTAssertEqual(recorder.states.count, 1, "start must publish once, synchronously")
        XCTAssertTrue(recorder.steps.isEmpty, "nothing sounds during the count-in")
    }

    func testTheCountInIsFourBeatsThenTheFirstStep() {
        let (session, clock, recorder) = makeSession()
        session.start(run)

        for expected in 2...4 {
            clock.advance(by: beat)
            XCTAssertEqual(session.snapshot.countInBeat, expected)
            XCTAssertEqual(session.snapshot.status, .countIn)
            XCTAssertTrue(recorder.steps.isEmpty, "still counting in at beat \(expected)")
        }

        clock.advance(by: beat)
        XCTAssertEqual(session.snapshot.status, .playing)
        XCTAssertEqual(session.snapshot.countInBeat, nil)
        XCTAssertEqual(session.snapshot.currentIndex, 0)
        XCTAssertEqual(recorder.steps.map(\.step), ["A"])
    }

    // MARK: - The run

    func testStepsAdvanceOneToABeatAndThenTheRunEnds() {
        let (session, clock, recorder) = makeSession()
        session.start(run)
        clock.advance(by: beat * 4) // through the count-in and onto step 0

        clock.advance(by: beat)
        XCTAssertEqual(recorder.steps.map(\.step), ["A", "B"])
        clock.advance(by: beat)
        XCTAssertEqual(recorder.steps.map(\.step), ["A", "B", "C"])
        XCTAssertEqual(recorder.steps.map(\.index), [0, 1, 2])

        clock.advance(by: beat)
        XCTAssertEqual(session.snapshot.status, .idle, "the run ends after its last step")
        XCTAssertEqual(session.snapshot.currentIndex, nil)
        XCTAssertEqual(session.snapshot.total, 0)
    }

    func testAnEmptyRunDoesNothing() {
        let (session, clock, recorder) = makeSession()
        session.start([])
        clock.advance(by: beat * 20)
        XCTAssertEqual(session.snapshot.status, .idle)
        XCTAssertTrue(recorder.steps.isEmpty)
    }

    // MARK: - Tempo

    func testTempoMovesThroughThePresetsAndClamps() {
        let (session, _, _) = makeSession()
        XCTAssertEqual(session.snapshot.tempoBpm, 80)
        XCTAssertEqual(session.slower(), 60)
        XCTAssertEqual(session.slower(), 40)
        XCTAssertEqual(session.slower(), 40, "clamps at the slowest preset")
        XCTAssertEqual(session.faster(), 60)
        XCTAssertEqual(session.faster(), 80)
        XCTAssertEqual(session.faster(), 100)
        XCTAssertEqual(session.faster(), 120)
        XCTAssertEqual(session.faster(), 120, "clamps at the fastest preset")
    }

    func testAnOffPresetTempoFallsBackToTheDefault() {
        let (session, _, _) = makeSession()
        XCTAssertEqual(session.setTempo(73), 80)
        XCTAssertEqual(session.setTempo(120), 120)
    }

    /// The detail that makes the tempo buttons feel connected: a change
    /// reschedules the *pending* beat rather than letting the old interval run
    /// out first.
    func testChangingTempoMidRunReschedulesThePendingBeat() {
        let (session, clock, recorder) = makeSession()
        session.start(run)
        clock.advance(by: beat * 4)
        XCTAssertEqual(recorder.steps.count, 1)

        // Halfway through the beat that would bring step 2, double the tempo.
        clock.advance(by: beat / 2)
        session.setTempo(40) // slower: 1.5s per beat
        XCTAssertEqual(recorder.steps.count, 1, "the pending step has not fired yet")

        // At the old tempo the step would have landed by now; at the new one it
        // must not have.
        clock.advance(by: beat / 2)
        XCTAssertEqual(recorder.steps.count, 1, "the step was not rescheduled at the new tempo")

        clock.advance(by: 60.0 / 40.0)
        XCTAssertEqual(recorder.steps.count, 2)
    }

    /// Tempo is the player's setting, not the run's, so it survives a stop.
    func testTempoSurvivesAStop() {
        let (session, _, _) = makeSession()
        _ = session.slower()
        session.stop()
        XCTAssertEqual(session.snapshot.tempoBpm, 60)
    }

    // MARK: - Cancellation

    func testAStoppedSessionEmitsNothingFurther() {
        let (session, clock, recorder) = makeSession()
        session.start(run)
        clock.advance(by: beat * 4)
        XCTAssertEqual(recorder.steps.count, 1)

        session.stop()
        XCTAssertGreaterThan(clock.pendingCount, 0, "work is still queued — this is the case a real clock hides")
        let statesAfterStop = recorder.states.count

        clock.advance(by: beat * 50)
        XCTAssertEqual(recorder.steps.count, 1, "no further steps after stop")
        XCTAssertEqual(recorder.states.count, statesAfterStop, "no further state after stop")
        XCTAssertEqual(session.snapshot.status, .idle)
    }

    func testStartingAgainCancelsTheRunInProgress() {
        let (session, clock, recorder) = makeSession()
        session.start(run)
        clock.advance(by: beat * 5)
        XCTAssertEqual(recorder.steps.map(\.step), ["A", "B"])

        session.start(["X"])
        clock.advance(by: beat * 10)
        XCTAssertEqual(recorder.steps.map(\.step), ["A", "B", "X"], "the abandoned run must not resume")
    }

    func testRapidStartStopCyclesLeaveNothingScheduled() {
        let (session, clock, recorder) = makeSession()
        for _ in 0..<50 {
            session.start(run)
            session.stop()
        }
        clock.advance(by: beat * 100)
        XCTAssertTrue(recorder.steps.isEmpty, "no run got far enough to sound a step")
        XCTAssertEqual(clock.pendingCount, 0, "work left scheduled after stop")
        XCTAssertEqual(session.snapshot.status, .idle)
    }

    // MARK: - Progression behaviour

    func testAProgressionHandsBackEachIndexInOrder() {
        let clock = ManualClock()
        let seen = Box<[Int]>([])
        let session = ProgressionSession(clock: clock, onStep: { index, _ in seen.value.append(index) })
        session.startProgression(total: 4, loop: false)

        clock.advance(by: beat * 4)
        XCTAssertEqual(seen.value, [0])
        clock.advance(by: beat * 3)
        XCTAssertEqual(seen.value, [0, 1, 2, 3])
        clock.advance(by: beat * 2)
        XCTAssertEqual(session.snapshot.status, .idle)
    }

    /// Looping restarts with no second count-in — the pulse is already
    /// established by the time the first pass ends.
    func testALoopingProgressionRestartsWithoutCountingInAgain() {
        let clock = ManualClock()
        let seen = Box<[Int]>([])
        let session = ProgressionSession(clock: clock, onStep: { index, _ in seen.value.append(index) })
        session.startProgression(total: 2, loop: true)

        clock.advance(by: beat * 4)
        clock.advance(by: beat * 4)
        XCTAssertEqual(seen.value, [0, 1, 0, 1, 0], "must cycle rather than stop")
        XCTAssertEqual(session.snapshot.status, .playing)
        XCTAssertNotEqual(session.snapshot.status, .countIn)

        session.stop()
        let count = seen.value.count
        clock.advance(by: beat * 20)
        XCTAssertEqual(seen.value.count, count, "a stopped loop must stop")
    }

    /// A chord usually gets a bar, not a beat.
    func testStepsCanBeHeldForSeveralBeats() {
        let clock = ManualClock()
        let seen = Box<[Int]>([])
        let session = ProgressionSession(clock: clock, onStep: { index, _ in seen.value.append(index) })
        session.startProgression(total: 3, loop: false, beatsPerStep: 4)

        clock.advance(by: beat * 4)
        XCTAssertEqual(seen.value, [0])
        clock.advance(by: beat * 3)
        XCTAssertEqual(seen.value, [0], "a four-beat step must not advance after one beat")
        clock.advance(by: beat)
        XCTAssertEqual(seen.value, [0, 1])
    }

    func testAProgressionOfNothingDoesNotStart() {
        let clock = ManualClock()
        let session = ProgressionSession(clock: clock)
        session.startProgression(total: 0, loop: false)
        clock.advance(by: beat * 20)
        XCTAssertEqual(session.snapshot.status, .idle)
        XCTAssertEqual(session.snapshot.total, 0)
    }
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
