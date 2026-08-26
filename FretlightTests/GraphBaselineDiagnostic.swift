#if DEBUG
import AVFoundation
import XCTest
@testable import Fretwork

/// TEMPORARY — workstream 003 Phase 0 baseline. Delete once recorded.
///
/// Starts the real `AudioEngine` against real hardware on both graph shapes
/// and prints the numbers the telemetry row shows the user: reported buffer
/// size, measured latency, and which path was taken. These are the regression
/// bar for the rest of the workstream; a change to monitoring latency is a
/// defect, not a trade-off.
final class GraphBaselineDiagnostic: XCTestCase {
    /// xcodebuild does not surface a test's stdout, so report to a file the
    /// harness can read back.
    private static let reportURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FRETWORK_BASELINE_REPORT"] ?? "/tmp/fretwork-baseline.txt")

    private func report(_ line: String) {
        print(line)
        let data = (line + "\n").data(using: .utf8)!
        if let handle = try? FileHandle(forWritingTo: Self.reportURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: Self.reportURL)
        }
    }

    private func measure(inputID: AudioDeviceID, outputID: AudioDeviceID, label: String) {
        let engine = AudioEngine()
        let samples = UnsafeMutableTransferBox<[PitchDisplayState]>([])
        let errors = UnsafeMutableTransferBox<[String]>([])

        let gotUpdate = expectation(description: "\(label) telemetry")
        gotUpdate.assertForOverFulfill = false
        engine.onUpdate = { state in
            samples.value.append(state)
            if samples.value.count >= 20 { gotUpdate.fulfill() }
        }
        engine.onError = { message in
            errors.value.append(message)
            gotUpdate.fulfill()
        }

        engine.start(inputDeviceID: inputID, outputDeviceID: outputID, monitorVolume: 0.5)
        wait(for: [gotUpdate], timeout: 10)
        // Let it run a little longer so the latency figures settle.
        Thread.sleep(forTimeInterval: 2)
        engine.stop()
        Thread.sleep(forTimeInterval: 0.5)

        if let error = errors.value.first {
            report("BASELINE \(label): ERROR \(error)")
            return
        }
        let latencies = samples.value.map(\.latencyMilliseconds).filter { $0 > 0 }.sorted()
        let direct = samples.value.last?.isDirectMonitoring ?? false
        let buffer = AudioDeviceEnumerator.bufferFrameSize(inputID).map(String.init) ?? "unknown"
        let median = latencies.isEmpty ? -1 : latencies[latencies.count / 2]
        report(String(
            format: "BASELINE %@: path=%@ buffer=%@ frames latency median=%.2fms min=%.2fms max=%.2fms n=%d",
            label,
            direct ? "duplex/direct" : "split/buffered",
            buffer,
            median,
            latencies.first ?? -1,
            latencies.last ?? -1,
            latencies.count
        ))
    }

    /// Phase 2: the player attached to a real device, not an offline graph.
    /// Confirms the render block is actually being pulled (voices retire on
    /// their own) and that nothing in the graph errors.
    private func measurePlayback(inputID: AudioDeviceID, outputID: AudioDeviceID, label: String) {
        let engine = AudioEngine()
        let errors = UnsafeMutableTransferBox<[String]>([])
        engine.onError = { errors.value.append($0) }
        engine.start(inputDeviceID: inputID, outputDeviceID: outputID, monitorVolume: 0.5)
        Thread.sleep(forTimeInterval: 1.5)

        let prepared = expectation(description: "library")
        let loadError = UnsafeMutableTransferBox<String?>(nil)
        let started = Date()
        engine.prepareSamplePlayback { message in
            loadError.value = message
            prepared.fulfill()
        }
        wait(for: [prepared], timeout: 60)
        let loadSeconds = Date().timeIntervalSince(started)
        if let message = loadError.value {
            report("PLAYBACK \(label): LOAD FAILED \(message)")
            engine.stop()
            return
        }
        Thread.sleep(forTimeInterval: 1.0)

        // A six-string strum, then a fast run, which is what exercises voice
        // stealing and the pool ceiling together.
        for string in 0..<6 {
            engine.playSample(string: string, fret: 0)
            Thread.sleep(forTimeInterval: 0.03)
        }
        Thread.sleep(forTimeInterval: 0.5)
        for fret in 0..<12 {
            engine.playSample(string: fret % 6, fret: fret)
            Thread.sleep(forTimeInterval: 0.08)
        }
        Thread.sleep(forTimeInterval: 3.0)

        engine.stop()
        Thread.sleep(forTimeInterval: 0.5)
        report(String(
            format: "PLAYBACK %@: library loaded in %.2fs, errors=%d %@",
            label, loadSeconds, errors.value.count, errors.value.first ?? ""
        ))
    }

    func testPlaybackOnRealHardware() throws {
        let inputs = AudioDeviceEnumerator.inputDevices()
        let outputs = AudioDeviceEnumerator.outputDevices()
        if let duplex = inputs.first(where: { input in
            outputs.contains { $0.id == input.id } && AudioDeviceEnumerator.isDuplexCapable(input.id)
        }) {
            measurePlayback(inputID: duplex.id, outputID: duplex.id, label: "duplex(\(duplex.name))")
        }
        if let input = inputs.first, let output = outputs.first(where: { $0.id != input.id }) {
            measurePlayback(inputID: input.id, outputID: output.id, label: "split(\(input.name) -> \(output.name))")
        }
    }

    func testBaseline() throws {
        let inputs = AudioDeviceEnumerator.inputDevices()
        let outputs = AudioDeviceEnumerator.outputDevices()
        report("BASELINE inputs: \(inputs.map { "\($0.id):\($0.name)" })")
        report("BASELINE outputs: \(outputs.map { "\($0.id):\($0.name)" })")

        // Duplex: a device serving both directions under one ID.
        if let duplex = inputs.first(where: { input in
            outputs.contains { $0.id == input.id } && AudioDeviceEnumerator.isDuplexCapable(input.id)
        }) {
            measure(inputID: duplex.id, outputID: duplex.id, label: "duplex(\(duplex.name))")
        } else {
            report("BASELINE: no duplex-capable device present")
        }

        // Split: deliberately mismatched input and output devices.
        if let input = inputs.first, let output = outputs.first(where: { $0.id != input.id }) {
            measure(inputID: input.id, outputID: output.id, label: "split(\(input.name) -> \(output.name))")
        } else {
            report("BASELINE: cannot form a split pair")
        }
    }
}

/// Lets the `@Sendable` engine callbacks accumulate results without tripping
/// strict concurrency. Test-only; the value is only read after `wait` returns.
final class UnsafeMutableTransferBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
#endif
