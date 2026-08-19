import Foundation

struct PitchDisplayState: Sendable {
    var frequency: Double?
    var confidence: Float = 0
    var level: Float = 0
    var latencyMilliseconds: Double = 0
    var bufferSize: Int = 0
    /// True when monitoring runs inside a single duplex render graph rather
    /// than crossing two engines through a ring buffer.
    var isDirectMonitoring: Bool = false
    var note: MappedNote?
}
