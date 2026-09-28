import XCTest
import AVFoundation
@testable import Fretwork

// MARK: - Fake session

/// Deterministic `IOSAudioSessionControlling`. No real `AVAudioSession` is
/// constructed, so the default suite satisfies C-11; the permission prompt can
/// also be *held* to test a stop landing mid-request.
@MainActor
final class FakeIOSAudioSession: IOSAudioSessionControlling {
    var recordPermission: IOSAudioRecordPermission = .granted
    private(set) var permissionRequests = 0
    /// Whether an `.undetermined` request resolves granted.
    var grantOnRequest = true
    /// When true, `requestRecordPermission()` suspends until `resumePermission`.
    var holdPermission = false
    private var heldPermission: CheckedContinuation<Bool, Never>?

    private(set) var setActiveValues: [Bool] = []
    private(set) var categories: [AVAudioSession.Category] = []
    var activationError: TestFailure?
    var categoryError: TestFailure?
    var sampleRate: Double = 48_000
    var inputChannelCount: Int = 1
    var inputLatency: TimeInterval = 0.012
    var ioBufferDuration: TimeInterval = 0.023

    var onInterruption: ((IOSAudioInterruption) -> Void)?
    var onRouteChange: ((IOSAudioRouteChangeReason) -> Void)?
    var onMediaServicesReset: (() -> Void)?

    func requestRecordPermission() async -> Bool {
        permissionRequests += 1
        if holdPermission {
            return await withCheckedContinuation { continuation in
                heldPermission = continuation
            }
        }
        if recordPermission == .undetermined, grantOnRequest { recordPermission = .granted }
        return recordPermission == .granted
    }

    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        if let categoryError { throw categoryError }
        categories.append(category)
    }

    func setActive(_ active: Bool) throws {
        setActiveValues.append(active)
        if let activationError { throw activationError }
    }

    func waitUntilPermissionRequested() async {
        let deadline = Date().addingTimeInterval(3)
        while heldPermission == nil, Date() < deadline {
            await Task.yield()
        }
    }

    func resumePermission(granted: Bool) {
        heldPermission?.resume(returning: granted)
        heldPermission = nil
    }

    func fireInterruption(kind: IOSAudioInterruption.Kind, shouldResume: Bool = false) {
        onInterruption?(IOSAudioInterruption(kind: kind, shouldResume: shouldResume))
    }

    func fireMediaServicesReset() { onMediaServicesReset?() }
    func fireRouteChange(_ reason: IOSAudioRouteChangeReason) { onRouteChange?(reason) }
}

// MARK: - Fake foreground

@MainActor
final class FakeIOSForegroundObserver: IOSForegroundObserving {
    var onForegroundChange: ((Bool) -> Void)?
    func fire(_ active: Bool) { onForegroundChange?(active) }
}

// MARK: - Fake graph

/// Counters shared by every graph a builder creates, so a test can assert
/// one-start/one-stop-per-cycle without holding every graph strongly (which
/// would defeat the deallocation assertions).
final class FakeIOSAudioGraphStats: @unchecked Sendable {
    private let lock = NSLock()
    private var _startCount = 0
    private var _stopCount = 0

    var startCount: Int { lock.lock(); defer { lock.unlock() }; return _startCount }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return _stopCount }
    func recordStart() { lock.lock(); _startCount += 1; lock.unlock() }
    func recordStop() { lock.lock(); _stopCount += 1; lock.unlock() }
}

final class FakeIOSAudioGraph: IOSAudioGraphHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let stats: FakeIOSAudioGraphStats
    private let startError: TestFailure?
    private var _isRunning = false
    private var _attachedPlayers: [SamplePlayer] = []
    private var _sampleRate: Double = 48_000

    init(stats: FakeIOSAudioGraphStats, startError: TestFailure?) {
        self.stats = stats
        self.startError = startError
    }

    var sampleRate: Double {
        get { locked { _sampleRate } }
        set { locked { _sampleRate = newValue } }
    }
    var isRunning: Bool { locked { _isRunning } }
    var attachedPlayers: [SamplePlayer] { locked { _attachedPlayers } }

    func start() throws {
        try locked {
            if let startError { throw startError }
            _isRunning = true
        }
        stats.recordStart()
    }

    func stop() {
        locked { _isRunning = false }
        stats.recordStop()
    }

    func attachPlayer(_ player: SamplePlayer) { locked { _attachedPlayers.append(player) } }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
}

final class FakeIOSAudioGraphBuilder: IOSAudioGraphBuilding, @unchecked Sendable {
    let stats = FakeIOSAudioGraphStats()
    private let lock = NSLock()
    private var _builds: [IOSAudioGraphLeg] = []
    private var weakGraphs: [WeakGraph] = []
    var buildError: TestFailure?
    var startError: TestFailure?

    private struct WeakGraph { weak var value: FakeIOSAudioGraph? }

    var builds: [IOSAudioGraphLeg] {
        lock.lock(); defer { lock.unlock() }
        return _builds
    }

    /// Only graph objects still alive. Used to prove superseded runs deallocate.
    var graphs: [FakeIOSAudioGraph] {
        lock.lock(); defer { lock.unlock() }
        return weakGraphs.compactMap(\.value)
    }

    var lastGraph: FakeIOSAudioGraph? { graphs.last }
    var graphStartCount: Int { stats.startCount }
    var graphStopCount: Int { stats.stopCount }

    func build(leg: IOSAudioGraphLeg,
               sessionSampleRate: Double,
               analysisRing: RingBuffer,
               chordRing: RingBuffer) throws -> IOSAudioGraphHandling {
        lock.lock()
        let error = buildError
        let startError = self.startError
        _builds.append(leg)
        lock.unlock()
        if let error { throw error }

        let graph = FakeIOSAudioGraph(stats: stats, startError: startError)
        lock.lock()
        weakGraphs.append(WeakGraph(value: graph))
        lock.unlock()
        return graph
    }
}

// MARK: - Test helpers

struct TestFailure: Error, Sendable, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
final class EventRecorder {
    private(set) var events: [AudioControllerEvent] = []
    func record(_ event: AudioControllerEvent) { events.append(event) }
    func clear() { events.removeAll() }

    var messages: [String] {
        events.compactMap { event in
            guard case .error(let message) = event else { return nil }
            return message
        }
    }

    var noteUpdateCount: Int {
        events.filter { if case .noteUpdate = $0 { return true } else { return false } }.count
    }

    var chordUpdateCount: Int {
        events.filter { if case .chordUpdate = $0 { return true } else { return false } }.count
    }

    var reconnectingCount: Int {
        events.filter { if case .reconnecting = $0 { return true } else { return false } }.count
    }

    var recoveredCount: Int {
        events.filter { if case .recovered = $0 { return true } else { return false } }.count
    }
}

final class PlayRecorder: @unchecked Sendable {
    struct Call: Sendable, Equatable {
        let string: Int
        let fret: Int
        let rate: Double
        let gain: Float
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    func record(_ call: Call) { lock.lock(); _calls.append(call); lock.unlock() }
}

/// A weak holder so the deallocation test can reassign the reference without
/// the compiler warning that a `weak var` local is never mutated.
final class WeakGraphRef {
    weak var graph: FakeIOSAudioGraph?
}

// MARK: - Tests

@MainActor
final class IOSAudioControllerTests: XCTestCase {
    private func makeController(
        permission: IOSAudioRecordPermission = .granted,
        plays: PlayRecorder? = nil
    ) -> (IOSAudioController, FakeIOSAudioSession, FakeIOSForegroundObserver, FakeIOSAudioGraphBuilder, EventRecorder) {
        let session = FakeIOSAudioSession()
        session.recordPermission = permission
        let foreground = FakeIOSForegroundObserver()
        let builder = FakeIOSAudioGraphBuilder()
        let recorder = EventRecorder()
        let play: @Sendable (SamplePlayer, Int, Int, Double, Float) -> Void
        if let plays {
            play = { _, string, fret, rate, gain in
                plays.record(.init(string: string, fret: fret, rate: rate, gain: gain))
            }
        } else {
            play = { player, string, fret, rate, gain in
                player.play(string: string, fret: fret, rateMultiplier: rate, gain: gain)
            }
        }
        let controller = IOSAudioController(
            session: session,
            foreground: foreground,
            graphBuilder: builder,
            playThroughPlayer: play
        )
        controller.onEvent = { [recorder] in recorder.record($0) }
        return (controller, session, foreground, builder, recorder)
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func loadLibrary(_ controller: IOSAudioController) async {
        let loaded = expectation(description: "library decoded")
        controller.prepareSamplePlayback { error in
            XCTAssertNil(error)
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 30)
    }

    // MARK: 1. Permission matrix

    func testDeniedPermissionEmitsErrorAndNeverActivates() async {
        let (controller, session, foreground, builder, recorder) = makeController(permission: .denied)
        foreground.fire(true)

        XCTAssertFalse(controller.start(), "a denied start issues nothing, so AppState must not clear its banner")
        XCTAssertEqual(controller.status, .permissionDenied)
        XCTAssertEqual(session.permissionRequests, 0)
        XCTAssertEqual(session.setActiveValues, [])
        XCTAssertEqual(builder.builds.count, 0)
        XCTAssertEqual(recorder.messages, ["Microphone permission is off. Enable it in Settings."])
    }

    func testGrantedPermissionSkipsTheRequestAndStartsListening() async {
        let (controller, session, foreground, builder, _) = makeController(permission: .granted)
        foreground.fire(true)

        XCTAssertTrue(controller.start())
        await controller.settleGraphWork()

        XCTAssertEqual(session.permissionRequests, 0, "an already-granted permission must not re-prompt")
        XCTAssertEqual(controller.status, .listening)
        XCTAssertEqual(session.setActiveValues, [true])
        XCTAssertEqual(builder.builds, [.captureAndOutput])
    }

    func testUndeterminedPermissionRequestsOnceThenRuns() async {
        let (controller, session, foreground, _, _) = makeController(permission: .undetermined)
        session.grantOnRequest = true
        foreground.fire(true)

        XCTAssertTrue(controller.start())
        await controller.settleGraphWork()

        XCTAssertEqual(session.permissionRequests, 1)
        XCTAssertEqual(controller.status, .listening)
        XCTAssertEqual(session.setActiveValues, [true])
    }

    func testUndeterminedPermissionDeniedSurfacesPermissionDenied() async {
        let (controller, session, foreground, builder, recorder) = makeController(permission: .undetermined)
        session.grantOnRequest = false
        foreground.fire(true)

        XCTAssertTrue(controller.start(), "the start was issued; the async outcome is what denies")
        await controller.settleGraphWork()

        XCTAssertEqual(session.permissionRequests, 1)
        XCTAssertEqual(controller.status, .permissionDenied)
        XCTAssertEqual(session.setActiveValues, [])
        XCTAssertEqual(builder.builds.count, 0)
        XCTAssertEqual(recorder.messages, ["Microphone permission is off. Enable it in Settings."])
    }

    // MARK: 2. Activation policy

    func testStartWhileBackgroundedDoesNotActivate() async {
        let (controller, session, foreground, builder, _) = makeController()
        foreground.fire(false)

        XCTAssertTrue(controller.start())
        await controller.settleGraphWork()

        XCTAssertEqual(session.setActiveValues, [])
        XCTAssertEqual(builder.builds.count, 0)
        XCTAssertFalse(controller.hasRunForTesting)

        // Foregrounding later is what builds.
        foreground.fire(true)
        await controller.settleGraphWork()
        XCTAssertEqual(session.setActiveValues, [true])
        XCTAssertEqual(controller.status, .listening)
    }

    func testForegroundStartActivatesOnceAndBackgroundDeactivates() async {
        let (controller, session, foreground, builder, _) = makeController()
        foreground.fire(true)
        XCTAssertTrue(controller.start())
        await controller.settleGraphWork()

        XCTAssertEqual(session.setActiveValues, [true])
        XCTAssertEqual(controller.status, .listening)
        XCTAssertEqual(controller.currentLeg, .captureAndOutput)

        foreground.fire(false)
        await controller.settleGraphWork()

        XCTAssertEqual(session.setActiveValues, [true, false])
        XCTAssertEqual(controller.status, .idle)
        XCTAssertFalse(controller.hasRunForTesting)
        XCTAssertEqual(builder.graphStopCount, 1)
    }

    // MARK: 3. Stop during the permission prompt

    func testStopDuringPermissionPromptLeavesIdleAndNeverActivates() async {
        let (controller, session, foreground, builder, _) = makeController(permission: .undetermined)
        session.holdPermission = true
        foreground.fire(true)

        XCTAssertTrue(controller.start())
        await session.waitUntilPermissionRequested()
        controller.stop()
        session.resumePermission(granted: true)
        await controller.settleGraphWork()

        XCTAssertEqual(controller.status, .idle)
        XCTAssertEqual(session.setActiveValues, [], "a grant landing after stop must not activate audio")
        XCTAssertEqual(builder.builds.count, 0)
        XCTAssertFalse(controller.hasRunForTesting)
    }

    // MARK: 4. Interruption / media reset / route

    func testInterruptionBeganReconnectsAndEndedRebuildsToRecovered() async {
        let (controller, session, foreground, builder, recorder) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()
        XCTAssertEqual(controller.status, .listening)

        session.fireInterruption(kind: .began)
        await controller.settleGraphWork()
        XCTAssertEqual(controller.status, .interrupted)
        XCTAssertEqual(recorder.reconnectingCount, 1)
        XCTAssertEqual(builder.graphStopCount, 1)

        session.fireInterruption(kind: .ended, shouldResume: true)
        await controller.settleGraphWork()
        XCTAssertEqual(controller.status, .listening)
        XCTAssertEqual(recorder.recoveredCount, 1)
        XCTAssertEqual(builder.builds.count, 2)
        XCTAssertEqual(builder.graphStartCount, 2)
    }

    func testInterruptionEndedWhenNotResumableStaysIdle() async {
        let (controller, session, foreground, builder, recorder) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()

        session.fireInterruption(kind: .began)
        await controller.settleGraphWork()
        session.fireInterruption(kind: .ended, shouldResume: false)
        await controller.settleGraphWork()

        XCTAssertEqual(controller.status, .idle)
        XCTAssertEqual(builder.builds.count, 1, "no rebuild without shouldResume")
        XCTAssertEqual(recorder.recoveredCount, 0)
    }

    func testInterruptionEndedRebuildFailureEmitsError() async {
        let (controller, session, foreground, builder, recorder) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()
        session.fireInterruption(kind: .began)
        await controller.settleGraphWork()

        builder.startError = TestFailure("the route refused to start")
        session.fireInterruption(kind: .ended, shouldResume: true)
        await controller.settleGraphWork()

        guard case .failed(let message) = controller.status else {
            return XCTFail("expected .failed, got \(controller.status)")
        }
        XCTAssertTrue(message.contains("refused to start"))
        XCTAssertEqual(recorder.messages.count, 1)
    }

    func testMediaServicesResetEmitsErrorThenRecovers() async {
        let (controller, session, foreground, builder, recorder) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()

        session.fireMediaServicesReset()
        await controller.settleGraphWork()

        XCTAssertEqual(controller.status, .listening)
        XCTAssertEqual(recorder.messages.count, 1)
        XCTAssertEqual(recorder.recoveredCount, 1)
        XCTAssertEqual(builder.builds.count, 2)
    }

    func testRouteChangeReasonMapping() {
        XCTAssertEqual(SystemIOSAudioSession.mapRouteChangeReason(.newDeviceAvailable), .newDeviceAvailable)
        XCTAssertEqual(SystemIOSAudioSession.mapRouteChangeReason(.oldDeviceUnavailable), .oldDeviceUnavailable)
        XCTAssertEqual(SystemIOSAudioSession.mapRouteChangeReason(.categoryChange), .categoryChange)
        XCTAssertEqual(SystemIOSAudioSession.mapRouteChangeReason(.override), .override)
        XCTAssertEqual(SystemIOSAudioSession.mapRouteChangeReason(.routeConfigurationChange), .unknown)
        XCTAssertEqual(SystemIOSAudioSession.mapRouteChangeReason(nil), .unknown)
    }

    func testRouteChangeIsRecordedAndStaysTransparent() async {
        let (controller, session, foreground, builder, _) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()

        session.fireRouteChange(.oldDeviceUnavailable)

        XCTAssertEqual(controller.lastRouteChange, .oldDeviceUnavailable)
        XCTAssertEqual(controller.status, .listening, "Phase 3 keeps route changes transparent")
        XCTAssertEqual(builder.builds.count, 1, "a route change must not rebuild the graph")
    }

    // MARK: 5. Sensitivity and chord gating

    func testSensitivityIsSharedWithTheWorkersWithoutARebuild() async {
        let (controller, _, foreground, builder, _) = makeController()
        controller.setSensitivity(0.7)
        XCTAssertEqual(controller.sensitivityValueForTesting, 0.7)

        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()
        XCTAssertEqual(controller.sensitivityValueForTesting, 0.7)
        XCTAssertEqual(builder.builds.count, 1)
    }

    func testChordDetectionToggleNeverRebuildsTheGraph() async {
        let (controller, _, foreground, builder, _) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()

        controller.setChordDetectionEnabled(true)
        controller.setChordDetectionEnabled(false)

        XCTAssertEqual(builder.builds.count, 1)
        XCTAssertEqual(builder.graphStartCount, 1)
        XCTAssertEqual(builder.graphStopCount, 0)
    }

    // MARK: 6. Sample wiring

    /// The first tap must not be silently dropped: decoding the library eagerly
    /// opens the output-only graph, so readiness is true before any play.
    func testPrepareSamplePlaybackEagerlyBuildsOutputOnlyGraph() async {
        let plays = PlayRecorder()
        let (controller, _, foreground, builder, _) = makeController(plays: plays)
        foreground.fire(true)

        await loadLibrary(controller)
        await controller.settleGraphWork()

        XCTAssertEqual(builder.builds.last, .outputOnly, "playback must not wait for a play attempt")
        XCTAssertEqual(controller.status, .idle,
                       "a playback-only run opens no microphone, so it must not report listening")
        XCTAssertTrue(controller.isSamplePlaybackReady)
        XCTAssertEqual(builder.lastGraph?.attachedPlayers.count, 1)

        controller.playSample(string: 0, fret: 0, tuning: Tunings.dropD)
        XCTAssertEqual(plays.calls.count, 1, "the first playSample after loading must reach the player")
        XCTAssertEqual(plays.calls.first?.string, 0)
        XCTAssertEqual(plays.calls.first?.fret, 0)
        XCTAssertEqual(plays.calls.first?.rate ?? 0, pow(2, -2.0 / 12.0), accuracy: 1e-9)
        XCTAssertEqual(plays.calls.first?.gain, 1)
    }

    func testListeningRunAttachesPlayerWhenLibraryLoads() async {
        let (controller, _, foreground, builder, _) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()
        XCTAssertEqual(builder.builds, [.captureAndOutput])
        XCTAssertEqual(builder.lastGraph?.attachedPlayers.count, 0)

        await loadLibrary(controller)
        await controller.settleGraphWork()

        XCTAssertEqual(builder.lastGraph?.attachedPlayers.count, 1)
        XCTAssertTrue(controller.isSamplePlaybackReady)
    }

    /// Starting to listen while a playback-only run exists must tear that run
    /// down exactly once, build the capture run, and carry the decoded player
    /// across so it stays ready.
    func testListeningSwitchTearsDownOutputOnlyAndReattachesPlayer() async {
        let (controller, _, foreground, builder, _) = makeController()
        foreground.fire(true)
        await loadLibrary(controller)
        await controller.settleGraphWork()
        XCTAssertEqual(controller.currentLeg, .outputOnly)
        let playerBefore = builder.lastGraph?.attachedPlayers.first
        XCTAssertNotNil(playerBefore)

        _ = controller.start()
        await controller.settleGraphWork()

        XCTAssertEqual(controller.currentLeg, .captureAndOutput)
        XCTAssertEqual(builder.builds, [.outputOnly, .captureAndOutput])
        XCTAssertEqual(builder.graphStopCount, 1, "the playback-only run is torn down exactly once")
        XCTAssertEqual(builder.lastGraph?.attachedPlayers.count, 1)
        XCTAssertTrue(builder.lastGraph?.attachedPlayers.first === playerBefore, "the decoded player is re-attached")
        XCTAssertTrue(controller.isSamplePlaybackReady)
    }

    // MARK: 7. Repeated foreground/background cycles

    func testFiftyForegroundCyclesActivateOnceEachAndDoNotDuplicateCallbacks() async {
        let (controller, session, foreground, builder, recorder) = makeController()
        _ = controller.start()   // foreground false: intent only, no activation

        for _ in 0..<50 {
            foreground.fire(true)
            await controller.settleGraphWork()
            foreground.fire(false)
            await controller.settleGraphWork()
        }

        XCTAssertEqual(session.setActiveValues.count, 100)
        XCTAssertTrue(stride(from: 0, to: 100, by: 2).allSatisfy { session.setActiveValues[$0] },
                      "every foreground entry activates once")
        XCTAssertTrue(stride(from: 1, to: 100, by: 2).allSatisfy { !session.setActiveValues[$0] },
                      "every background exit deactivates once")
        XCTAssertEqual(builder.builds.count, 50, "one engine per foreground cycle, no leaks")
        XCTAssertEqual(builder.graphStartCount, 50)
        XCTAssertEqual(builder.graphStopCount, 50)

        // One live run, then one synthetic publication each: exactly one event.
        foreground.fire(true)
        await controller.settleGraphWork()
        let analysis = controller.currentAnalysisWorkerForTesting
        let chord = controller.currentChordWorkerForTesting
        XCTAssertNotNil(analysis)
        XCTAssertNotNil(chord)
        recorder.clear()
        analysis?.onUpdate?(PitchDisplayState(), 0)
        chord?.onUpdate?(ChordDisplayState())
        _ = await waitUntil { recorder.noteUpdateCount == 1 && recorder.chordUpdateCount == 1 }
        await Task.yield()
        XCTAssertEqual(recorder.noteUpdateCount, 1, "a rebuild must not leave a second worker subscription")
        XCTAssertEqual(recorder.chordUpdateCount, 1)
    }

    /// The transition chain must not retain stopped runs. Before the fix each
    /// completed closure held its old run until a later enqueue, so 50 cycles
    /// kept 50 stopped engines alive.
    func testForegroundCyclesDeallocateStoppedRuns() async {
        let (controller, _, foreground, builder, _) = makeController()
        foreground.fire(true)
        _ = controller.start()
        await controller.settleGraphWork()

        let firstGraph = WeakGraphRef()
        firstGraph.graph = builder.lastGraph
        XCTAssertNotNil(firstGraph.graph)
        XCTAssertEqual(builder.graphs.count, 1)

        for _ in 0..<5 {
            foreground.fire(false)
            await controller.settleGraphWork()
            foreground.fire(true)
            await controller.settleGraphWork()
        }

        XCTAssertNil(firstGraph.graph, "a stopped run's engine must not be retained by the transition chain")
        XCTAssertEqual(builder.graphs.count, 1, "only the live run's graph may remain")
    }

    // MARK: 8. Release

    func testReleasingTheControllerStopsTheGraph() async {
        let session = FakeIOSAudioSession()
        let foreground = FakeIOSForegroundObserver()
        let builder = FakeIOSAudioGraphBuilder()
        var controller: IOSAudioController? = IOSAudioController(
            session: session,
            foreground: foreground,
            graphBuilder: builder
        )
        foreground.fire(true)
        _ = controller?.start()
        await controller?.settleGraphWork()
        XCTAssertEqual(builder.graphStopCount, 0)

        controller = nil

        XCTAssertEqual(builder.graphStopCount, 1, "deinit must stop the engine it owns")
    }
}
