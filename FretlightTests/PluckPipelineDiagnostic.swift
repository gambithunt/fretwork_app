#if DEBUG
import XCTest
@testable import Fretwork

/// Drives the whole capture pipeline with a synthesised *plucked string*
/// rather than a sine wave.
///
/// Every constant in the recorder and the verifier was tuned against pure
/// tones, which are perfectly periodic, start instantly and never decay. A
/// real string is none of those things: it has a noisy inharmonic attack, a
/// weak fundamental relative to its harmonics, and an amplitude that falls
/// away the whole time. Karplus-Strong reproduces all three, so this is the
/// closest thing to a real take that does not need a guitar in the room.
final class PluckPipelineDiagnostic: XCTestCase {
    private static let rate = 48_000.0

    /// Karplus-Strong: a burst of noise round a delay line the length of one
    /// period, low-passed on each pass. Harmonically rich at the attack,
    /// decaying toward the fundamental — which is what makes it a fair test.
    private func pluck(frequency: Double, seconds: Double, amplitude: Float, rate: Double = rate) -> [Float] {
        let period = Int((rate / frequency).rounded())
        var generator = SystemRandomNumberGenerator()
        var line = (0..<period).map { _ in Float.random(in: -1...1, using: &generator) }
        var out = [Float]()
        out.reserveCapacity(Int(rate * seconds))
        var index = 0
        // Just under 1 so the note decays over a couple of seconds, as a
        // wound low string does.
        let damping: Float = 0.9985
        for _ in 0..<Int(rate * seconds) {
            let value = line[index]
            out.append(value * amplitude)
            let next = line[(index + 1) % period]
            line[index] = (value + next) * 0.5 * damping
            index = (index + 1) % period
        }
        return out
    }

    private func midi(_ string: Int, _ fret: Int) -> Int {
        Tunings.standard.openMIDINotes[string] + fret
    }

    private func frequency(_ string: Int, _ fret: Int) -> Double {
        440 * pow(2, Double(midi(string, fret) - 69) / 12)
    }

    /// Runs a pluck through the real recorder — noise floor, onset gate,
    /// decay detection — and then the real verifier, and prints what each
    /// stage decided.
    /// `xcodebuild` does not surface a test's stdout, so results go to a file.
    private static let reportPath = "/tmp/fretwork-pluck-diagnostic.txt"

    private func report(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: Self.reportPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: Self.reportPath))
        }
    }

    func testPluckThroughTheWholePipeline() throws {
        try? FileManager.default.removeItem(atPath: Self.reportPath)
        FileManager.default.createFile(atPath: Self.reportPath, contents: nil)

        // The last case carries a realistic input noise floor. A near-silent
        // one is what let the original single-threshold bug hide: with almost
        // no room tone the onset gate sat near its own minimum, so a decaying
        // string never fell back under it and every take ran full length. On a
        // real DI the floor is orders of magnitude higher, the gate rises with
        // it, and the note drops under it about a second in.
        let cases: [(name: String, string: Int, fret: Int, amplitude: Float, floor: Float)] = [
            ("low E open", 0, 0, 0.35, 0.0005),
            ("low E fret 5", 0, 5, 0.35, 0.0005),
            ("A open", 1, 0, 0.35, 0.0005),
            ("D fret 7", 3, 7, 0.35, 0.0005),
            ("high e fret 12", 5, 12, 0.35, 0.0005),
            ("low E open, quiet", 0, 0, 0.08, 0.0005),
            ("low E open, noisy input", 0, 0, 0.35, 0.01)
        ]

        for (name, string, fret, amplitude, floor) in cases {
            let ring = RingBuffer()
            let recorder = SampleRecorder(ring: ring)
            let box = TakeBox()
            recorder.onTake = { box.take = $0 }
            recorder.start(sampleRate: Self.rate)
            defer { recorder.stop() }

            // A little room tone first, so the noise floor is measured from
            // something rather than from digital silence.
            feed(ring, samples: (0..<8192).map { _ in Float.random(in: -floor...floor) })
            Thread.sleep(forTimeInterval: 0.05)
            recorder.arm()
            Thread.sleep(forTimeInterval: 0.02)

            let note = pluck(frequency: frequency(string, fret), seconds: 2.5, amplitude: amplitude)
            feed(ring, samples: note)
            feed(ring, samples: [Float](repeating: 0, count: 48_000))

            let deadline = Date().addingTimeInterval(4)
            while box.take == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }

            guard let take = box.take else {
                report("\(name): NO TAKE CAPTURED — onset never fired, or the take never finished")
                return XCTFail("\(name): the recorder captured nothing from a plucked string")
            }
            let verdict = TakeVerifier.verify(take, string: string, fret: fret)
            report("\(name): \(verdict)")
            report("    \(TakeVerifier.diagnostics(take, string: string, fret: fret))")
            guard case .accepted = verdict else {
                return XCTFail("\(name): a clean plucked string must be accepted, got \(verdict)")
            }
            // The tail is the point of sampling a string. Onset and decay used
            // to share a threshold, which cut every take off about a second
            // in — right as the note got going. A 2.5s pluck must survive as
            // substantially more than its attack.
            let seconds = Double(take.samples.count) / take.sampleRate
            XCTAssertGreaterThan(seconds, 1.5, "\(name): take is \(String(format: "%.2f", seconds))s — the tail was cut off")
        }
    }

    /// Writes in ring-sized bites so nothing is dropped by overflow.
    private func feed(_ ring: RingBuffer, samples: [Float]) {
        var offset = 0
        while offset < samples.count {
            let count = min(1024, samples.count - offset)
            var slice = Array(samples[offset..<offset + count])
            slice.withUnsafeMutableBufferPointer {
                ring.write($0.baseAddress!, count: count, captureTime: 0)
            }
            offset += count
            Thread.sleep(forTimeInterval: 0.0015)
        }
    }
}

private final class TakeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SampleRecorder.Take?
    var take: SampleRecorder.Take? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
#endif
