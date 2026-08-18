import Accelerate
import Foundation
import MachO
import Darwin

final class AudioAnalysisWorker: @unchecked Sendable {
    private let ring: RingBuffer
    private let queue = DispatchQueue(label: "com.fretlight.analysis", qos: .userInitiated)
    private let detector = PitchDetector()
    private var window = Array(repeating: Float.zero, count: 2048)
    private var incoming = Array(repeating: Float.zero, count: 1024)
    private var history: [Int] = []
    private var lastMIDI: Int?
    private var lastFrequency: Double = 0
    private var lastDetection: ContinuousClock.Instant?
    private var lastPublish = ContinuousClock.now
    private var running: Int32 = 0
    var onUpdate: (@Sendable (PitchDisplayState, UInt64) -> Void)?

    init(ring: RingBuffer) { self.ring = ring }

    func start(sampleRate: Double, bufferSize: Int) {
        OSAtomicCompareAndSwap32Barrier(0, 1, &running)
        queue.async { [weak self] in self?.consume(sampleRate: sampleRate, bufferSize: bufferSize) }
    }
    func stop() { OSAtomicCompareAndSwap32Barrier(1, 0, &running) }

    private func consume(sampleRate: Double, bufferSize: Int) {
        while OSAtomicAdd32Barrier(0, &running) == 1 {
            // Read the newest chunk into scratch first — only once we know it's
            // available do we slide the window and splice the chunk into the tail.
            // (Writing straight into `window` and then shifting over it would
            // overwrite the samples we just read with stale data, which is what
            // was happening before: the window never actually saw new audio.)
            let didRead = incoming.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 1024) }
            guard didRead else { Thread.sleep(forTimeInterval: 0.002); continue }
            window.withUnsafeMutableBufferPointer { pointer in
                memmove(pointer.baseAddress!, pointer.baseAddress! + 1024, 1024 * MemoryLayout<Float>.stride)
                _ = incoming.withUnsafeBufferPointer { newer in
                    memmove(pointer.baseAddress! + 1024, newer.baseAddress!, 1024 * MemoryLayout<Float>.stride)
                }
            }
            let rms = window.withUnsafeBufferPointer { data -> Float in
                var value: Float = 0; vDSP_rmsqv(data.baseAddress!, 1, &value, vDSP_Length(data.count)); return value
            }
            let result = detector.detect(samples: window, sampleRate: sampleRate)
            let now = ContinuousClock.now
            guard now - lastPublish >= .milliseconds(33) else { continue }
            lastPublish = now
            let capture = ring.currentCaptureTime()
            var display = PitchDisplayState(level: rms, latencyMilliseconds: 0, bufferSize: bufferSize)
            var hasCurrentDetection = false
            if let result, result.confidence > 0.78, let mapped = NoteMapper.map(frequency: result.frequency) {
                history.append(mapped.midiNote); if history.count > 5 { history.removeFirst() }
                let median = history.sorted()[history.count / 2]
                if lastMIDI == nil || abs(median - lastMIDI!) <= 1 || history.filter({ $0 == median }).count >= 3 { lastMIDI = median }
                lastFrequency = result.frequency
                lastDetection = now
                hasCurrentDetection = true
                display.confidence = result.confidence
            } else { history.removeAll(keepingCapacity: true) }
            // A short hold prevents the display from blinking out during the
            // naturally aperiodic final cycles of a decaying guitar note.
            let isWithinHold = lastDetection.map { now - $0 < .milliseconds(180) } ?? false
            if let stable = lastMIDI, hasCurrentDetection || isWithinHold {
                let stableFrequency = 440 * pow(2, Double(stable - 69) / 12)
                display.frequency = lastFrequency
                display.note = NoteMapper.map(frequency: stableFrequency)
                if var note = display.note {
                    note = MappedNote(name: note.name, octave: note.octave, midiNote: note.midiNote, cents: 1200 * log2(lastFrequency / stableFrequency), positions: note.positions)
                    display.note = note
                }
            } else {
                lastMIDI = nil
                lastDetection = nil
            }
            onUpdate?(display, capture)
        }
    }
}
