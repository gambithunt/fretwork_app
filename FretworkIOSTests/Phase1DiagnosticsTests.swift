import XCTest
import Foundation
@testable import Fretwork

/// Covers the pure pieces of the Phase 1 diagnostic line: the host-time latency
/// conversion, the CPU scale, and the exact wording. The device-only parts
/// (Mach sampling, `AVAudioSession`) are exercised by running the harness.
final class Phase1DiagnosticFormatterTests: XCTestCase {
    func testLatencyMillisecondsAtOneToOneTimebase() {
        XCTAssertEqual(
            Phase1DiagnosticFormatter.latencyMilliseconds(
                captureHostTime: 1_000,
                publishHostTime: 1_001_000,
                timebaseNumer: 1,
                timebaseDenom: 1
            ),
            1.0,
            accuracy: 1e-9
        )
    }

    func testLatencyMillisecondsHonoursNonUnityTimebase() {
        // Apple silicon reports 125/3: 24_000 host ticks == 1 ms.
        XCTAssertEqual(
            Phase1DiagnosticFormatter.latencyMilliseconds(
                captureHostTime: 500,
                publishHostTime: 24_500,
                timebaseNumer: 125,
                timebaseDenom: 3
            ),
            1.0,
            accuracy: 1e-9
        )
    }

    func testLatencyMillisecondsRejectsMissingOrNonMonotonicStamps() {
        // No capture stamp yet (ring never written).
        XCTAssertEqual(
            Phase1DiagnosticFormatter.latencyMilliseconds(
                captureHostTime: 0, publishHostTime: 5_000, timebaseNumer: 1, timebaseDenom: 1
            ),
            0
        )
        // Publish clock behind the capture stamp: report nothing, never underflow.
        XCTAssertEqual(
            Phase1DiagnosticFormatter.latencyMilliseconds(
                captureHostTime: 5_000, publishHostTime: 4_000, timebaseNumer: 1, timebaseDenom: 1
            ),
            0
        )
        // Degenerate timebase.
        XCTAssertEqual(
            Phase1DiagnosticFormatter.latencyMilliseconds(
                captureHostTime: 1, publishHostTime: 2, timebaseNumer: 1, timebaseDenom: 0
            ),
            0
        )
    }

    func testThermalWordsAreShortAndStable() {
        XCTAssertEqual(Phase1DiagnosticFormatter.thermalWord(.nominal), "nominal")
        XCTAssertEqual(Phase1DiagnosticFormatter.thermalWord(.fair), "fair")
        XCTAssertEqual(Phase1DiagnosticFormatter.thermalWord(.serious), "serious")
        XCTAssertEqual(Phase1DiagnosticFormatter.thermalWord(.critical), "critical")
    }

    func testCPUPercentScalesByThreadUsageScale() {
        // A fully busy core reports 1000 scaled units.
        XCTAssertEqual(Phase1DiagnosticFormatter.cpuPercent(scaledUsage: 1000), 100)
        XCTAssertEqual(Phase1DiagnosticFormatter.cpuPercent(scaledUsage: 250), 25)
        XCTAssertEqual(Phase1DiagnosticFormatter.cpuPercent(scaledUsage: 0), 0)
    }

    func testSessionLineFormatsLatenciesInMilliseconds() {
        let line = Phase1DiagnosticFormatter.sessionLine(
            Phase1SessionMetrics(inputLatency: 0.012, ioBufferDuration: 0.005)
        )
        XCTAssertEqual(line, "phase1-session inputLatencyMs=12.00 ioBufferMs=5.00")
    }

    func testCPUThermalSuffixWording() {
        let suffix = Phase1DiagnosticFormatter.cpuThermalSuffix(
            cpuPercent: 12.34,
            thermalState: .fair
        )
        XCTAssertEqual(suffix, " cpu=12.3 thermal=fair")
    }

    func testProcessCPUPercentIsNonNegativeAndFinite() {
        // Exercises the Mach `task_threads`/`thread_basic_info` path end to end.
        let cpu = Phase1ProcessMetrics.currentCPUPercent()
        XCTAssertTrue(cpu.isFinite)
        XCTAssertGreaterThanOrEqual(cpu, 0)
    }

    /// End-to-end wiring: a host-time stamp taken when samples enter the
    /// pipeline must come back out as a non-zero `latencyMs` on the published
    /// detection. This is what a device run reads off the console.
    func testHostStampedSamplesProduceNonZeroLatency() async {
        let pipeline = Phase1AnalysisPipeline()
        let detected = expectation(description: "Detected A4 with a latency figure")
        detected.assertForOverFulfill = false
        pipeline.onUpdate = { telemetry in
            if telemetry.latestPitch.note?.midiNote == 69, telemetry.latestPitch.latencyMilliseconds > 0 {
                detected.fulfill()
            }
        }

        let feeder = Phase1SyntheticFeeder(pipeline: pipeline)
        feeder.start()
        await fulfillment(of: [detected], timeout: 2.0)
        feeder.stop()

        XCTAssertGreaterThan(pipeline.snapshot().latestPitch.latencyMilliseconds, 0)
    }
}
