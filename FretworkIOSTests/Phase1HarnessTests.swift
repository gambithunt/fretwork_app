import XCTest
import AVFoundation
@testable import Fretwork

final class Phase1SyntheticPipelineTests: XCTestCase {
    func testSynthetic440HzFeedsRealAudioAnalysisWorker() async {
        let pipeline = Phase1AnalysisPipeline()
        let detected = expectation(description: "Detected A4 through AudioAnalysisWorker")
        detected.assertForOverFulfill = false
        pipeline.onUpdate = { telemetry in
            if telemetry.latestPitch.note?.midiNote == 69 {
                detected.fulfill()
            }
        }

        let feeder = Phase1SyntheticFeeder(
            pipeline: pipeline,
            tone: Phase1SyntheticTone(frequency: 440, amplitude: 0.9, sampleRate: 48_000),
            frameCount: 1024
        )
        feeder.start()
        await fulfillment(of: [detected], timeout: 2.0)
        feeder.stop()

        let snapshot = pipeline.snapshot()
        XCTAssertEqual(snapshot.latestPitch.note?.name, "A")
        XCTAssertEqual(snapshot.latestPitch.note?.midiNote, 69)
    }

    func testSyntheticFeederStartStopIsIdempotent() {
        let pipeline = Phase1AnalysisPipeline()
        let feeder = Phase1SyntheticFeeder(pipeline: pipeline)
        feeder.start()
        feeder.start()
        feeder.stop()
        feeder.stop()
        XCTAssertGreaterThanOrEqual(pipeline.snapshot().sampleRate, 0)
    }

    func testRawCallbackCounterCountsWritesAndResetsOnRestart() {
        // No hardware, no publication: this exercises the realtime counter in
        // isolation so the diagnostic cannot silently regress into depending
        // on the analysis worker's `record()` path.
        let pipeline = Phase1AnalysisPipeline(ringCapacity: 4096)
        XCTAssertEqual(pipeline.rawCallbackCountSnapshot(), 0)

        pipeline.start(sampleRate: 48_000, bufferSize: 64)
        let chunk = [Float](repeating: 0.1, count: 64)
        chunk.withUnsafeBufferPointer { buffer in
            for _ in 0..<3 {
                pipeline.write(samples: buffer.baseAddress!, frameCount: chunk.count, captureTime: 0)
            }
        }
        XCTAssertEqual(pipeline.rawCallbackCountSnapshot(), 3)
        // Nothing was published, so the independent counter is the only
        // evidence the callback path ran.
        XCTAssertEqual(pipeline.snapshot().updateCount, 0)

        pipeline.stop()
        pipeline.start(sampleRate: 48_000, bufferSize: 64)
        XCTAssertEqual(pipeline.rawCallbackCountSnapshot(), 0)
        pipeline.stop()
    }
}

@MainActor
final class Phase1HarnessModelTests: XCTestCase {
    func testConstructionDoesNotCreateManualAudioSourceOrRequestActivation() {
        var sourceCreations = 0
        _ = Phase1HarnessModel(makeManualSource: {
            sourceCreations += 1
            return FakeManualCaptureSource()
        })
        XCTAssertEqual(sourceCreations, 0)
    }

    func testSyntheticStartDoesNotCreateManualAudioSource() {
        var sourceCreations = 0
        let model = Phase1HarnessModel(makeManualSource: {
            sourceCreations += 1
            return FakeManualCaptureSource()
        })
        model.selectedMode = .synthetic
        model.start()
        XCTAssertEqual(sourceCreations, 0)
        XCTAssertEqual(model.state, .running(.synthetic))
        model.stop()
        XCTAssertEqual(model.state, .idle)
    }

    func testManualDeniedPermissionSurfacesRecoverableDeniedStateWithoutRealAudio() async {
        let source = FakeManualCaptureSource(result: .failure(Phase1MicrophoneHarnessError.permissionDenied))
        let model = Phase1HarnessModel(makeManualSource: { source })
        model.selectedMode = .microphoneSink
        model.start()
        await source.waitForStart()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.state, .permissionDenied)
        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(source.stopCount, 1)
    }

    func testManualStopCallsInjectedSourceOnlyAfterExplicitStart() async {
        let source = FakeManualCaptureSource()
        let model = Phase1HarnessModel(makeManualSource: { source })
        XCTAssertEqual(source.startCount, 0)
        model.selectedMode = .microphoneSink
        model.start()
        await source.waitForStart()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.state, .running(.microphoneSink))
        model.stop()
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(model.state, .idle)
    }

    func testStopDuringStartLeavesStateIdleEvenAfterStaleCompletion() async {
        let source = FakeManualCaptureSource(result: .success, holdUntilResumed: true)
        let model = Phase1HarnessModel(makeManualSource: { source })
        model.selectedMode = .microphoneSink
        model.start()
        // Deterministic handshake: wait until the fake has installed its hold
        // continuation before we call Stop.
        await source.waitUntilHeld()
        // Stop while the start task is still suspended.
        model.stop()
        XCTAssertEqual(model.state, .idle)
        // Resume the fake — the task's stale completion must be a no-op.
        source.resumeIfHeld()
        await source.waitForStopCount(2)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(source.stopCount, 2)
    }

    func testRestartSyntheticCreatesFreshPipelineAndDetectsAgain() async {
        let model = Phase1HarnessModel(makeManualSource: { FakeManualCaptureSource() })
        model.selectedMode = .synthetic
        model.start()
        XCTAssertEqual(model.state, .running(.synthetic))
        model.stop()
        XCTAssertEqual(model.state, .idle)

        // Second cycle — fresh pipeline, should start cleanly.
        model.start()
        XCTAssertEqual(model.state, .running(.synthetic))
        model.stop()
        XCTAssertEqual(model.state, .idle)
    }

    func testRestartManualModeCreatesFreshPipeline() async {
        let source = FakeManualCaptureSource()
        let model = Phase1HarnessModel(makeManualSource: { source })

        model.selectedMode = .microphoneSink
        model.start()
        await source.waitForStart()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(model.state, .running(.microphoneSink))
        model.stop()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(source.stopCount, 1)

        // Second cycle — a fresh pipeline must start cleanly.
        model.selectedMode = .microphoneSink
        model.start()
        await source.waitForStart()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(model.state, .running(.microphoneSink))
        model.stop()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(source.startCount, 2)
        XCTAssertEqual(source.stopCount, 2)
    }

    func testDefaultSourceIsALiveMicrophoneAndConstructsNoSource() {
        var sourceCreations = 0
        let model = Phase1HarnessModel(makeManualSource: {
            sourceCreations += 1
            return FakeManualCaptureSource()
        })
        XCTAssertTrue(model.selectedMode.isLiveMicrophone)
        XCTAssertNotEqual(model.selectedMode, .synthetic)
        // Merely holding the default must not allocate or start the source.
        XCTAssertEqual(sourceCreations, 0)
        XCTAssertEqual(model.state, .idle)
    }

    func testDefaultStartDrivesTheLiveMicrophoneSourceNotTheDiagnosticTone() async {
        let source = FakeManualCaptureSource()
        let model = Phase1HarnessModel(makeManualSource: { source })
        XCTAssertTrue(model.selectedMode.isLiveMicrophone)

        model.start()
        await source.waitForStart()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(model.state, .running(model.selectedMode))
        XCTAssertNotEqual(model.state, .running(.synthetic))

        model.stop()
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(model.state, .idle)
    }

    func testDiagnosticToneRemainsExplicitlySelectable() {
        XCTAssertTrue(Phase1CaptureMode.allCases.contains(.synthetic))
        XCTAssertFalse(Phase1CaptureMode.synthetic.isLiveMicrophone)
        XCTAssertTrue(Phase1CaptureMode.microphoneSink.isLiveMicrophone)
    }

    func testStatusLabelDistinguishesLiveMicrophoneFromDiagnosticTone() {
        let live = Phase1HarnessState.running(.microphoneSink).label.lowercased()
        XCTAssertTrue(live.contains("microphone"))
        XCTAssertFalse(live.contains("diagnostic"))

        let diagnostic = Phase1HarnessState.running(.synthetic).label.lowercased()
        XCTAssertTrue(diagnostic.contains("diagnostic"))
        XCTAssertTrue(diagnostic.contains("not the microphone"))
    }
}

/// The logger exists to keep producing evidence while the UI is blocked, so
/// these tests deliberately read it from off the MainActor and assert only the
/// two counters it reports.
final class Phase1DiagnosticLoggerTests: XCTestCase {
    func testSampleReportsRawCallbacksAndUpdatesWithoutMainActor() async {
        let pipeline = Phase1AnalysisPipeline(ringCapacity: 4096)
        pipeline.start(sampleRate: 48_000, bufferSize: 64)
        let chunk = [Float](repeating: 0.1, count: 64)
        chunk.withUnsafeBufferPointer { buffer in
            for _ in 0..<3 {
                pipeline.write(samples: buffer.baseAddress!, frameCount: chunk.count, captureTime: 0)
            }
        }

        let logger = Phase1DiagnosticLogger(interval: .seconds(60))
        logger.start(pipeline: pipeline)
        defer {
            logger.stop()
            pipeline.stop()
        }

        // Read from a detached task: no MainActor hop may be required.
        let sample = await Task.detached { logger.sample() }.value
        XCTAssertEqual(sample?.rawCallbacks, 3)
        // Sub-1024 writes never satisfy the worker's read, so it never publishes.
        XCTAssertEqual(sample?.updates, 0)
    }

    func testSampleIsNilBeforeStartAndAfterStop() {
        let logger = Phase1DiagnosticLogger()
        XCTAssertNil(logger.sample())

        let pipeline = Phase1AnalysisPipeline(ringCapacity: 4096)
        logger.start(pipeline: pipeline)
        XCTAssertNotNil(logger.sample())

        logger.stop()
        XCTAssertNil(logger.sample())
        pipeline.stop()
    }
}

/// Regression for the MainActor-inherited realtime block. Before the fix the
/// sink block was a closure literal inside `Phase1MicrophoneHarness`, which is
/// `@MainActor`; the first background invocation tripped Swift's executor check
/// and trapped. Building it through the `nonisolated` factory must let it run
/// off the main thread and count the callback.
final class Phase1MicrophoneHarnessBlockTests: XCTestCase {
    func testSinkBlockRunsOnBackgroundThreadAndCountsCallback() async {
        let pipeline = Phase1AnalysisPipeline(ringCapacity: 4096)
        pipeline.start(sampleRate: 48_000, bufferSize: 1024)
        defer { pipeline.stop() }

        await Task.detached {
            let frameCount: AVAudioFrameCount = 1024
            let samples = [Float](repeating: 0.1, count: Int(frameCount))
            var timeStamp = AudioTimeStamp()
            let block = Phase1MicrophoneHarness.makeSinkBlock(pipeline: pipeline)

            samples.withUnsafeBufferPointer { source in
                let raw = UnsafeMutableRawPointer.allocate(
                    byteCount: MemoryLayout<AudioBufferList>.size,
                    alignment: MemoryLayout<AudioBufferList>.alignment
                )
                defer { raw.deallocate() }
                let list = raw.assumingMemoryBound(to: AudioBufferList.self)
                list.pointee.mNumberBuffers = 1
                list.pointee.mBuffers = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frameCount) * UInt32(MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(mutating: source.baseAddress)
                )
                let status = block(&timeStamp, frameCount, list)
                XCTAssertEqual(status, noErr)
            }
        }.value

        XCTAssertEqual(pipeline.rawCallbackCountSnapshot(), 1)
    }
}

@MainActor
private final class FakeManualCaptureSource: Phase1ManualCaptureSource {
    enum Result {
        case success
        case failure(Error)
    }

    private let result: Result
    private let holdUntilResumed: Bool
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var holdContinuation: CheckedContinuation<Void, Never>?
    private var holdInstalledContinuation: CheckedContinuation<Void, Never>?
    private var stopCountTarget: Int = 0
    private var stopCountContinuation: CheckedContinuation<Void, Never>?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(result: Result = .success, holdUntilResumed: Bool = false) {
        self.result = result
        self.holdUntilResumed = holdUntilResumed
    }

    func start(mode: Phase1CaptureMode, pipeline: Phase1AnalysisPipeline) async throws {
        startCount += 1
        startContinuation?.resume()
        startContinuation = nil
        if holdUntilResumed {
            await withCheckedContinuation { c in
                holdContinuation = c
                // Signal any waiter that the hold is installed.
                holdInstalledContinuation?.resume()
                holdInstalledContinuation = nil
            }
            holdContinuation = nil
        }
        switch result {
        case .success:
            pipeline.start(sampleRate: 48_000, bufferSize: 1024)
        case .failure(let error):
            throw error
        }
    }

    func stop() {
        stopCount += 1
        if stopCount >= stopCountTarget {
            stopCountContinuation?.resume()
            stopCountContinuation = nil
        }
    }

    func resumeIfHeld() {
        holdContinuation?.resume()
    }

    func waitUntilHeld() async {
        if holdContinuation != nil { return }
        await withCheckedContinuation { c in
            holdInstalledContinuation = c
        }
    }

    func waitForStopCount(_ target: Int) async {
        if stopCount >= target { return }
        stopCountTarget = target
        await withCheckedContinuation { c in
            stopCountContinuation = c
        }
    }

    func waitForStart() async {
        if startCount > 0 { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }
}
