import Darwin
import Foundation

struct Phase1AnalysisTelemetry: Sendable {
    var updateCount: Int = 0
    var lastCaptureTime: UInt64 = 0
    var lastCallbackFrameCount: Int = 0
    var callbackFrameHistogram: [Int: Int] = [:]
    var sampleRate: Double = 0
    var bufferSize: Int = 0
    var latestPitch = PitchDisplayState()

    var latestNoteLabel: String {
        guard let note = latestPitch.note else { return "—" }
        return "\(note.name)\(note.octave)"
    }
}

/// Lock-free SPSC ring for frame-count events from the audio callback.
/// Single producer (realtime I/O thread), single consumer (drained under lock
/// in `record()`). Overflow silently drops — a debug histogram need not be
/// lossless.
private final class FrameEventRing: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Int32>
    private let capacity: Int
    private var writeIndex: Int32 = 0
    private var readIndex: Int32 = 0

    init(capacity: Int = 64) {
        self.capacity = capacity
        self.buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    /// Realtime-safe: stores one frame count. Drops silently on overflow.
    func write(_ value: Int32) {
        let wi = OSAtomicAdd32Barrier(0, &writeIndex)
        let ri = OSAtomicAdd32Barrier(0, &readIndex)
        guard (wi - ri) < Int32(capacity) else { return }
        buffer[Int(wi % Int32(capacity))] = value
        OSAtomicAdd32Barrier(1, &writeIndex)
    }

    /// Drains all pending events. Called from the analysis worker callback
    /// (not from the realtime I/O thread).
    func drain() -> [Int32] {
        let ri = OSAtomicAdd32Barrier(0, &readIndex)
        let wi = OSAtomicAdd32Barrier(0, &writeIndex)
        guard wi > ri else { return [] }
        var result: [Int32] = []
        result.reserveCapacity(Int(wi - ri))
        var r = ri
        while r < wi {
            result.append(buffer[Int(r % Int32(capacity))])
            r += 1
        }
        OSAtomicAdd32Barrier(Int32(result.count), &readIndex)
        return result
    }
}

/// Tiny iOS-only analysis harness around the real shared detector path.
///
/// This intentionally stops at `AudioAnalysisWorker`: no `AppState`, no Mac
/// engine and no microphone graph are involved unless the manual Phase 1 source
/// explicitly starts one.
final class Phase1AnalysisPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let ring: RingBuffer
    private let sensitivity: SensitivitySettings
    private let worker: AudioAnalysisWorker
    private var telemetry = Phase1AnalysisTelemetry()
    private var isRunning = false
    /// Lock-free event ring for callback frame-counts, drained under the
    /// telemetry lock in `record()`.
    private let frameEventRing = FrameEventRing()
    /// Independent realtime callback counter. The frame-event ring above is
    /// only drained when the analysis worker publishes (`record()`), so it
    /// reads zero whenever the worker is silent even if capture is running.
    /// This counter is incremented lock-free in `write(...)` and read by the
    /// UI poll, so "is the capture callback firing at all?" stays answerable
    /// without depending on analysis publication.
    private var rawCallbackCount: Int32 = 0

    var onUpdate: (@Sendable (Phase1AnalysisTelemetry) -> Void)?

    init(ringCapacity: Int = 65_536, sensitivityValue: Double = SensitivitySettings.defaultValue) {
        ring = RingBuffer(capacity: ringCapacity)
        sensitivity = SensitivitySettings()
        sensitivity.value = sensitivityValue
        worker = AudioAnalysisWorker(ring: ring, sensitivity: sensitivity)
        worker.onUpdate = { [weak self] display, captureTime in
            self?.record(display: display, captureTime: captureTime)
        }
    }

    func start(sampleRate: Double, bufferSize: Int) {
        lock.lock()
        guard !isRunning else { lock.unlock(); return }
        isRunning = true
        // Each run starts a fresh count so a stale value cannot be mistaken
        // for activity from this session.
        let staleCount = OSAtomicAdd32Barrier(0, &rawCallbackCount)
        _ = OSAtomicCompareAndSwap32Barrier(staleCount, 0, &rawCallbackCount)
        telemetry.sampleRate = sampleRate
        telemetry.bufferSize = bufferSize
        lock.unlock()
        worker.start(sampleRate: sampleRate, bufferSize: bufferSize)
    }

    func stop() {
        lock.lock()
        let shouldStop = isRunning
        isRunning = false
        lock.unlock()
        if shouldStop { worker.stop() }
    }

    func write(samples: UnsafePointer<Float>, frameCount: Int, captureTime: UInt64) {
        guard frameCount > 0 else { return }
        // Realtime-safe: no lock or allocation on the I/O thread. Counts every
        // callback even if the ring is full and drops the samples.
        _ = OSAtomicIncrement32Barrier(&rawCallbackCount)
        ring.write(samples, count: frameCount, captureTime: captureTime)
        // Lock-free frame count recording — no NSLock or allocation in the
        // realtime callback.
        frameEventRing.write(Int32(frameCount))
    }

    func snapshot() -> Phase1AnalysisTelemetry {
        lock.lock(); defer { lock.unlock() }
        return telemetry
    }

    /// Reads the realtime capture-callback counter without taking the telemetry
    /// lock, so polling it at a few hertz cannot block the audio callback or
    /// the analysis worker. Independent of `updateCount` in the telemetry.
    func rawCallbackCountSnapshot() -> Int {
        Int(OSAtomicAdd32Barrier(0, &rawCallbackCount))
    }

    private func record(display: PitchDisplayState, captureTime: UInt64) {
        lock.lock()
        telemetry.latestPitch = display
        telemetry.lastCaptureTime = captureTime
        telemetry.updateCount += 1
        // Drain lock-free frame events: the last event is the latest frame
        // count; all events feed the histogram.
        let events = frameEventRing.drain()
        for fc in events {
            telemetry.callbackFrameHistogram[Int(fc), default: 0] += 1
        }
        if let last = events.last {
            telemetry.lastCallbackFrameCount = Int(last)
        }
        let current = telemetry
        lock.unlock()
        onUpdate?(current)
    }
}
