#if DEBUG
import Darwin
import Foundation

/// Session-level timing reported by `AVAudioSession` once capture has started.
///
/// Logged once per run so a console reader can add the same *excluded* fixed
/// latencies back onto the per-update `latencyMs` figure:
///
///   total ≈ latencyMs + inputLatency + (one ioBufferDuration)
///
/// `inputLatency` is the hardware/HAL latency already elapsed before the sink
/// callback ever sees a buffer; `ioBufferDuration` is the size of one I/O
/// block and bounds how stale the most recent buffer can be.
struct Phase1SessionMetrics: Equatable, Sendable {
    var inputLatency: TimeInterval
    var ioBufferDuration: TimeInterval
}

/// Host-time clock conversion for the diagnostic latency figure. Kept as
/// `UInt32` statics rather than a stored `mach_timebase_info_data_t` because
/// the raw C struct is not `Sendable` under strict concurrency.
enum Phase1LatencyClock {
    static let timebaseNumer: UInt32 = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.numer
    }()

    static let timebaseDenom: UInt32 = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom
    }()
}

/// Pure formatting and math behind the Phase 1 diagnostic line. Split out so
/// the arithmetic and the exact wording can be unit-tested without an audio
/// device or a live `ProcessInfo`.
enum Phase1DiagnosticFormatter {
    /// Converts a host-time delta into milliseconds.
    ///
    /// Returns 0 for a missing (`captureHostTime == 0`) or non-monotonic
    /// (publish earlier than capture) pair rather than underflowing. The
    /// `Double` pipeline mirrors `AudioEngine.makeAnalysisWorker`.
    static func latencyMilliseconds(
        captureHostTime: UInt64,
        publishHostTime: UInt64,
        timebaseNumer: UInt32,
        timebaseDenom: UInt32
    ) -> Double {
        guard captureHostTime != 0,
              publishHostTime > captureHostTime,
              timebaseDenom != 0
        else { return 0 }
        let elapsed = publishHostTime - captureHostTime
        return Double(elapsed) * Double(timebaseNumer) / Double(timebaseDenom) / 1_000_000
    }

    /// Short single word for `ProcessInfo.thermalState`.
    static func thermalWord(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    /// `thread_basic_info.cpu_usage` is scaled by `TH_USAGE_SCALE` (1000), so
    /// a summed raw usage of 1000 is one fully-busy core (100%).
    static func cpuPercent(scaledUsage: Double) -> Double {
        scaledUsage / 1000 * 100
    }

    /// The one-off start-of-run line carrying the fixed session latencies.
    static func sessionLine(_ metrics: Phase1SessionMetrics) -> String {
        String(
            format: "phase1-session inputLatencyMs=%.2f ioBufferMs=%.2f",
            metrics.inputLatency * 1000,
            metrics.ioBufferDuration * 1000
        )
    }

    /// Appended to every periodic line.
    static func cpuThermalSuffix(
        cpuPercent: Double,
        thermalState: ProcessInfo.ThermalState
    ) -> String {
        String(format: " cpu=%.1f", cpuPercent) + " thermal=\(thermalWord(thermalState))"
    }
}

/// Collects whole-process CPU usage from Mach thread info.
///
/// Called **only** from `Phase1DiagnosticLogger`'s detached task — never from
/// the audio callback or the analysis worker. `task_threads` allocates a port
/// array, so this must not run anywhere realtime.
enum Phase1ProcessMetrics {
    /// Sum of every live thread's scaled CPU usage, converted to percent.
    ///
    /// Returns 0 if Mach refuses the query; a diagnostic line is better with a
    /// missing number than with a trap.
    static func currentCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threadList
        else { return 0 }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: UnsafeMutableRawPointer(threadList)),
                vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride)
            )
        }

        var totalScaledUsage: Double = 0
        for index in 0..<Int(threadCount) {
            let thread = threadList[index]
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), rebound, &count)
                }
            }
            if result == KERN_SUCCESS {
                totalScaledUsage += Double(info.cpu_usage)
            }
            // task_threads hands back a send right per thread; release it so a
            // 0.5 Hz sampler does not leak ports over a long device run.
            mach_port_deallocate(mach_task_self_, thread)
        }
        return Phase1DiagnosticFormatter.cpuPercent(scaledUsage: totalScaledUsage)
    }
}

#endif
