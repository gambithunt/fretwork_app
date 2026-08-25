#if DEBUG
import XCTest
@testable import Fretwork

/// Thread-safe capture of a callback's value. The recorder's callbacks are
/// `@Sendable` and fire on its own queue, so a plain captured `var` will not
/// compile under strict concurrency.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

final class SampleRecorderTests: XCTestCase {
    private static let chunk = 1024
    /// A deliberately low rate. It only feeds the recorder's duration
    /// arithmetic, so it makes the six-second cap and the decay hold reachable
    /// in a few dozen buffers instead of a few hundred.
    private static let rate = 8_000.0

    /// Writes chunks at roughly one per millisecond so the recorder's own
    /// drain keeps up — `RingBuffer.write` drops on overflow, and its capacity
    /// is only 32 chunks.
    private func pump(_ ring: RingBuffer, amplitude: Float, chunks: Int) {
        var buffer = [Float](repeating: amplitude, count: Self.chunk)
        for _ in 0..<chunks {
            buffer.withUnsafeMutableBufferPointer {
                ring.write($0.baseAddress!, count: Self.chunk, captureTime: 0)
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func testAnArmedRecorderCapturesFromOnsetUntilTheNoteDecays() {
        let ring = RingBuffer()
        let recorder = SampleRecorder(ring: ring)
        let captured = Box<SampleRecorder.Take?>(nil)
        let finished = expectation(description: "take finished")
        recorder.onTake = { take in
            captured.value = take
            finished.fulfill()
        }
        recorder.start(sampleRate: Self.rate)
        defer { recorder.stop() }

        pump(ring, amplitude: 0, chunks: 4)
        recorder.arm()
        pump(ring, amplitude: 0.5, chunks: 4)
        pump(ring, amplitude: 0, chunks: 6)

        wait(for: [finished], timeout: 5)
        let take = try? XCTUnwrap(captured.value)
        XCTAssertEqual(take?.sampleRate, Self.rate)
        XCTAssertEqual(take?.peak ?? 0, 0.5, accuracy: 0.001)
        // At least the struck portion, and not the whole silent tail that
        // followed it.
        XCTAssertGreaterThanOrEqual(take?.samples.count ?? 0, 4 * Self.chunk)
        XCTAssertLessThan(take?.samples.count ?? 0, 14 * Self.chunk)
    }

    func testAnUnarmedRecorderReportsLevelButCapturesNothing() {
        let ring = RingBuffer()
        let recorder = SampleRecorder(ring: ring)
        let takes = Box(0)
        let sawSignal = Box(false)
        recorder.onTake = { _ in takes.value += 1 }
        recorder.onLevel = { if $0 > 0.1 { sawSignal.value = true } }
        recorder.start(sampleRate: Self.rate)
        defer { recorder.stop() }

        pump(ring, amplitude: 0.5, chunks: 10)
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertTrue(sawSignal.value, "the level meter must work before arming")
        XCTAssertEqual(takes.value, 0, "nothing may be captured until armed")
    }

    func testDisarmingMidTakeDiscardsIt() {
        let ring = RingBuffer()
        let recorder = SampleRecorder(ring: ring)
        let takes = Box(0)
        recorder.onTake = { _ in takes.value += 1 }
        recorder.start(sampleRate: Self.rate)
        defer { recorder.stop() }

        pump(ring, amplitude: 0, chunks: 3)
        recorder.arm()
        pump(ring, amplitude: 0.5, chunks: 4)
        recorder.disarm()
        pump(ring, amplitude: 0, chunks: 6)
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(takes.value, 0, "an abandoned take must not be delivered")
    }

    func testATakeIsCappedRatherThanGrowingWithoutBound() {
        let ring = RingBuffer()
        let recorder = SampleRecorder(ring: ring)
        let captured = Box<SampleRecorder.Take?>(nil)
        let finished = expectation(description: "take capped")
        recorder.onTake = { take in
            captured.value = take
            finished.fulfill()
        }
        recorder.start(sampleRate: Self.rate)
        defer { recorder.stop() }

        pump(ring, amplitude: 0, chunks: 3)
        recorder.arm()
        // Never decays: without the cap this would accumulate for as long as
        // audio keeps arriving.
        pump(ring, amplitude: 0.5, chunks: 60)

        wait(for: [finished], timeout: 5)
        let take = captured.value
        let frames = take?.samples.count ?? 0
        XCTAssertGreaterThan(frames, 0)
        // Six seconds at the test rate, plus at most the buffer that crossed
        // the threshold.
        XCTAssertLessThanOrEqual(frames, Int(6 * Self.rate) + Self.chunk)
        // The take must end *mid-signal*. An upper bound alone would also be
        // satisfied by the ring starving, which is not the thing under test —
        // only the cap can cut a take while the string is still sounding.
        XCTAssertNotEqual(take?.samples.last, 0)
    }

    func testFinishingATakeReturnsToIdleSoATailCannotStartAnother() {
        let ring = RingBuffer()
        let recorder = SampleRecorder(ring: ring)
        let takes = Box(0)
        let finished = expectation(description: "first take")
        recorder.onTake = { _ in
            takes.value += 1
            if takes.value == 1 { finished.fulfill() }
        }
        recorder.start(sampleRate: Self.rate)
        defer { recorder.stop() }

        pump(ring, amplitude: 0, chunks: 3)
        recorder.arm()
        pump(ring, amplitude: 0.5, chunks: 4)
        pump(ring, amplitude: 0, chunks: 6)
        wait(for: [finished], timeout: 5)

        // A second strike with no second arm must be ignored.
        pump(ring, amplitude: 0.5, chunks: 4)
        pump(ring, amplitude: 0, chunks: 6)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(takes.value, 1)
    }
}
#endif
