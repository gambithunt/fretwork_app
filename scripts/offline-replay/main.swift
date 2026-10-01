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
///
///   --all  print every published frame (~30 Hz), not just note changes,
///          to inspect confidence decay on low notes.

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

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: offline-replay <mono.wav> [sensitivity 0..1] [--all]") }

let wavURL = URL(fileURLWithPath: args[1])
let (sampleRate, decoded) = parseWAV(at: wavURL)

let sensitivity = SensitivitySettings()
if args.count >= 3, let value = Double(args[2]), !args[2].hasPrefix("-") {
    sensitivity.value = min(max(value, 0), 1)
}
let printAll = args.contains("--all")

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
