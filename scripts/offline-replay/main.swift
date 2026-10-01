import Foundation
import Darwin

/// Offline replay harness for the shared note-detection path.
///
/// Feeds a mono WAV through the *real* `AudioAnalysisWorker` + `PitchDetector`
/// + `SensitivitySettings` + `RingBuffer` at the WAV's own sample rate and
/// prints the confirmed-note timeline (one line per note change, plus `none`
/// transitions) in the same shape as `SessionLogFormat.noteLine`, so captures
/// can be tuned without a device and without changing app code.
///
/// Real-time pacing is deliberate: `AudioAnalysisWorker`'s 33 ms publish
/// throttle and its 180 ms hold both run on wall-clock time, so replaying
/// faster than real time would change the confirmed-note timeline. A 25 s
/// capture therefore takes 25 s to replay.
///
/// Usage:
///   offline-replay <mono.wav> [sensitivity 0..1] [--all]
///   offline-replay --synthetic [sensitivity 0..1]
///
///   --all       print every published frame (~30 Hz), not just note changes,
///               to inspect confidence decay on low notes.
///   --synthetic generate A2→E4→A2→E4 sine steps (clean and noisy onset) and
///               report the ms from each leap's first new-pitch sample to the
///               frequency readout and the note-name switch, plus the lag.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("offline-replay: \(message)\n".utf8))
    exit(1)
}

// MARK: - WAV parsing (mono Float32 / PCM16 / PCM24)

func parseWAV(at url: URL) -> (sampleRate: Double, frames: [Float]) {
    guard let data = try? Data(contentsOf: url) else { fail("cannot read \(url.path)") }
    guard data.count > 44,
          String(data: data.subdata(in: 0..<4), encoding: .ascii) == "RIFF",
          String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE" else {
        fail("\(url.path) is not a RIFF/WAVE file")
    }

    func le16(_ i: Int) -> UInt16 { UInt16(data[i]) | (UInt16(data[i + 1]) << 8) }
    func le32(_ i: Int) -> UInt32 {
        UInt32(data[i]) | (UInt32(data[i + 1]) << 8) | (UInt32(data[i + 2]) << 16) | (UInt32(data[i + 3]) << 24)
    }

    var format: UInt16 = 0
    var channels: UInt16 = 0
    var sampleRate: UInt32 = 0
    var bitsPerSample: UInt16 = 0
    var frameData: Data?

    var offset = 12
    while offset + 8 <= data.count {
        let id = String(data: data.subdata(in: offset..<offset + 4), encoding: .ascii) ?? ""
        let size = Int(le32(offset + 4))
        let bodyStart = offset + 8
        let bodyEnd = min(bodyStart + size, data.count)
        switch id {
        case "fmt ":
            format = le16(bodyStart)
            channels = le16(bodyStart + 2)
            sampleRate = le32(bodyStart + 4)
            bitsPerSample = le16(bodyStart + 14)
        case "data":
            frameData = data.subdata(in: bodyStart..<bodyEnd)
        default:
            break
        }
        offset = bodyEnd + (size % 2)
    }

    guard let frameData, !frameData.isEmpty else { fail("\(url.path) has no data chunk") }
    guard channels == 1 else { fail("\(url.path) is \(channels)-channel; a mono capture is required") }
    guard sampleRate > 0 else { fail("\(url.path) has no sample rate") }

    let bytesPerSample = Int(bitsPerSample / 8)
    var frames: [Float] = []
    frames.reserveCapacity(frameData.count / max(bytesPerSample, 1))

    switch (format, bitsPerSample) {
    case (3, 32): // IEEE float
        var i = 0
        while i + 4 <= frameData.count {
            let bits = UInt32(frameData[i]) | (UInt32(frameData[i + 1]) << 8)
                | (UInt32(frameData[i + 2]) << 16) | (UInt32(frameData[i + 3]) << 24)
            frames.append(Float(bitPattern: bits))
            i += 4
        }
    case (1, 16): // PCM16
        var i = 0
        while i + 2 <= frameData.count {
            let raw = Int16(bitPattern: UInt16(frameData[i]) | (UInt16(frameData[i + 1]) << 8))
            frames.append(Float(raw) / 32_768)
            i += 2
        }
    case (1, 24): // PCM24
        var i = 0
        while i + 3 <= frameData.count {
            var v = Int32(frameData[i]) | (Int32(frameData[i + 1]) << 8) | (Int32(frameData[i + 2]) << 16)
            if v & 0x800000 != 0 { v |= ~0xFFFFFF }
            frames.append(Float(v) / 8_388_608)
            i += 3
        }
    default:
        fail("\(url.path): unsupported WAV format \(format)/\(bitsPerSample)-bit (expected mono float32, pcm16 or pcm24)")
    }

    guard !frames.isEmpty else { fail("\(url.path) decoded to zero frames") }
    return (Double(sampleRate), frames)
}

// MARK: - Formatting (mirrors SessionLogFormat)

func decibels(_ level: Float) -> Double { 20 * log10(max(Double(level), 0.000_001)) }

func noteName(_ note: MappedNote?) -> String {
    note.map { "\($0.name)\($0.octave)" } ?? "none"
}

func noteLine(t: Double, display: PitchDisplayState, sampleRate: Double) -> String {
    let name = noteName(display.note)
    let cents = display.note.map { String(format: "%.1f", $0.cents) } ?? "-"
    let hz = display.frequency.map { String(format: "%.2f", $0) } ?? "-"
    let period: String
    if let frequency = display.frequency, frequency > 0, sampleRate > 0 {
        period = String(format: "%.1f", sampleRate / frequency)
    } else {
        period = "-"
    }
    return "SESSION t=\(String(format: "%.3f", t)) note=\(name) cents=\(cents)"
        + " conf=\(String(format: "%.3f", display.confidence))"
        + " level=\(String(format: "%.1f", decibels(display.level)))"
        + " hz=\(hz) period=\(period)"
}

func uptimeNanos() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

// MARK: - Synthetic leap test

struct Leap {
    let name: String
    let sample: Int
    let targetMIDI: Int
    let targetFrequency: Double
}

struct PublishedFrame: Sendable { let t: Double; let frequency: Double?; let midi: Int? }

final class PublishedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [PublishedFrame] = []
    func append(_ frame: PublishedFrame) { lock.lock(); entries.append(frame); lock.unlock() }
    func snapshot() -> [PublishedFrame] { lock.lock(); defer { lock.unlock() }; return entries }
}

func midiFrequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

/// A2 (110 Hz) → E4 (329.6 Hz) and back, repeated, so the first note is
/// confirmed before each leap and the worker takes the *changed*-note path
/// rather than the new-note path. `noisyOnset` adds a ~20 ms noise burst at
/// the start of each new pitch to mimic a pluck attack.
func syntheticLeapFrames(sampleRate: Double, noisyOnset: Bool) -> (frames: [Float], leaps: [Leap]) {
    let a2 = 45
    let e4 = 64
    let segmentLength = Int(sampleRate * 0.6)
    let pattern = [a2, e4, a2, e4]
    var frames: [Float] = []
    // A second of quiet room tone first so the running noise floor is already
    // populated. Without it, a single nil-detection frame at a leap boundary
    // drags the (still mostly empty) floor up to the note's own level and
    // gates the next note out — an artifact of the synthetic back-to-back
    // signal, not of the leap rule under test.
    let roomTone = Int(sampleRate * 1.0)
    frames.append(contentsOf: (0..<roomTone).map { _ in Float.random(in: -0.001...0.001) })
    var leaps: [Leap] = []
    for (index, midi) in pattern.enumerated() {
        if index > 0 {
            leaps.append(Leap(name: index % 2 == 1 ? "A2→E4" : "E4→A2",
                              sample: frames.count, targetMIDI: midi,
                              targetFrequency: midiFrequency(midi)))
        }
        let frequency = midiFrequency(midi)
        var segment = (0..<segmentLength).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) * 0.5 }
        if noisyOnset, index > 0 {
            let onset = min(Int(sampleRate * 0.02), segment.count)
            for i in 0..<onset { segment[i] += Float.random(in: -0.25...0.25) }
        }
        frames.append(contentsOf: segment)
    }
    return (frames, leaps)
}

/// Runs the synthetic leaps through the real worker and reports, for each
/// leap, the wall-clock time from the first new-pitch sample to (a) the
/// frequency readout landing within ±60¢ of the target and (b) the note name
/// switching — plus the lag between the two.
func runSyntheticLeapTest(sensitivity: SensitivitySettings) {
    let sampleRate = 48_000.0
    for noisy in [false, true] {
        let (decoded, leaps) = syntheticLeapFrames(sampleRate: sampleRate, noisyOnset: noisy)
        var frames = decoded
        let remainder = frames.count % 1024
        if remainder != 0 { frames.append(contentsOf: repeatElement(Float(0), count: 1024 - remainder)) }

        let ring = RingBuffer(capacity: 65_536)
        let worker = AudioAnalysisWorker(ring: ring, sensitivity: sensitivity)
        let log = PublishedLog()
        let feedStart = uptimeNanos()
        worker.onUpdate = { display, _ in
            let t = Double(uptimeNanos() - feedStart) / 1_000_000_000
            log.append(PublishedFrame(t: t, frequency: display.frequency, midi: display.note?.midiNote))
        }
        worker.start(sampleRate: sampleRate, bufferSize: 1024)

        var chunk = [Float](repeating: 0, count: 1024)
        var chunkIndex = 0
        while chunkIndex * 1024 < frames.count {
            chunk.withUnsafeMutableBufferPointer { buffer in
                for i in 0..<1024 { buffer[i] = frames[chunkIndex * 1024 + i] }
            }
            chunk.withUnsafeBufferPointer { buffer in
                ring.write(buffer.baseAddress!, count: 1024, captureTime: UInt64(chunkIndex * 1024))
            }
            chunkIndex += 1
            let pacedFrames = min(chunkIndex * 1024, decoded.count)
            let targetNanos = feedStart + UInt64(Double(pacedFrames) / sampleRate * 1_000_000_000)
            while uptimeNanos() < targetNanos { Thread.sleep(forTimeInterval: 0.002) }
        }
        while ring.backlogFrames() > 0 { Thread.sleep(forTimeInterval: 0.01) }
        Thread.sleep(forTimeInterval: 0.25)
        worker.stop()

        func fmt(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "never" }
        let published = log.snapshot()
        print("=== synthetic \(noisy ? "noisy onset" : "clean") ===")
        for leap in leaps {
            let leapTime = Double(leap.sample) / sampleRate
            var freqSwitch: Double?
            var nameSwitch: Double?
            for p in published where p.t >= leapTime - 0.001 {
                if freqSwitch == nil, let f = p.frequency, abs(1200 * log2(f / leap.targetFrequency)) <= 60 {
                    freqSwitch = p.t
                }
                if nameSwitch == nil, p.midi == leap.targetMIDI { nameSwitch = p.t }
                if freqSwitch != nil, nameSwitch != nil { break }
            }
            let freqMs = freqSwitch.map { ($0 - leapTime) * 1000 }
            let nameMs = nameSwitch.map { ($0 - leapTime) * 1000 }
            let lagMs = (freqSwitch != nil && nameSwitch != nil) ? (nameSwitch! - freqSwitch!) * 1000 : nil
            print("\(leap.name): freq=\(fmt(freqMs))ms name=\(fmt(nameMs))ms lag=\(fmt(lagMs))ms")
        }
    }
}

// MARK: - Main

let args = CommandLine.arguments
let printAll = args.contains("--all")
let synthetic = args.contains("--synthetic")

let sensitivity = SensitivitySettings()
if let valueArg = args.dropFirst().first(where: { Double($0) != nil && !$0.hasPrefix("-") }) {
    sensitivity.value = min(max(Double(valueArg)!, 0), 1)
}

if synthetic {
    runSyntheticLeapTest(sensitivity: sensitivity)
    exit(0)
}

guard args.count >= 2 else { fail("usage: offline-replay <mono.wav> [sensitivity 0..1] [--all] [--synthetic]") }

let wavURL = URL(fileURLWithPath: args[1])
let (sampleRate, decoded) = parseWAV(at: wavURL)

// Pad to a whole number of 1024-frame chunks so the worker's all-or-nothing
// `read(into:count: 1024)` consumes the final partial chunk (silence-padded).
var frames = decoded
let remainder = frames.count % 1024
if remainder != 0 { frames.append(contentsOf: repeatElement(Float(0), count: 1024 - remainder)) }
let realFrameCount = decoded.count

let ring = RingBuffer(capacity: 65_536)
let worker = AudioAnalysisWorker(ring: ring, sensitivity: sensitivity)

let feedStart = uptimeNanos()
var lastPrintedNote: String?
var noteEventCount = 0

worker.onUpdate = { display, _ in
    let t = Double(uptimeNanos() - feedStart) / 1_000_000_000
    let name = noteName(display.note)
    if printAll || name != lastPrintedNote {
        print(noteLine(t: t, display: display, sampleRate: sampleRate))
        if name != lastPrintedNote { lastPrintedNote = name; noteEventCount += 1 }
    }
}

worker.start(sampleRate: sampleRate, bufferSize: 1024)

var chunk = [Float](repeating: 0, count: 1024)
var chunkIndex = 0
while chunkIndex * 1024 < frames.count {
    chunk.withUnsafeMutableBufferPointer { buffer in
        for i in 0..<1024 { buffer[i] = frames[chunkIndex * 1024 + i] }
    }
    chunk.withUnsafeBufferPointer { buffer in
        ring.write(buffer.baseAddress!, count: 1024, captureTime: UInt64(chunkIndex * 1024))
    }
    chunkIndex += 1
    // Pace in real time; once past the real (unpadded) frames the target is
    // already reached and the trailing silence is written immediately.
    let pacedFrames = min(chunkIndex * 1024, realFrameCount)
    let targetNanos = feedStart + UInt64(Double(pacedFrames) / sampleRate * 1_000_000_000)
    while uptimeNanos() < targetNanos {
        Thread.sleep(forTimeInterval: 0.002)
    }
}

// Let the worker drain the ring, then stop it.
while ring.backlogFrames() > 0 { Thread.sleep(forTimeInterval: 0.01) }
Thread.sleep(forTimeInterval: 0.25)
worker.stop()

FileHandle.standardError.write(Data("offline-replay: done — \(noteEventCount) note events, \(realFrameCount) frames at \(Int(sampleRate)) Hz\n".utf8))
