import Foundation

struct PitchDisplayState: Sendable {
    var frequency: Double?
    var confidence: Float = 0
    var level: Float = 0
    var latencyMilliseconds: Double = 0
    var bufferSize: Int = 0
    var note: MappedNote?
}
