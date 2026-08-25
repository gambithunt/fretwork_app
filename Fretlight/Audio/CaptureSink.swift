import AVFoundation
import Darwin

/// Takes captured audio out of the graph from inside the capture engine's own
/// render callback, replacing `installTap(onBus:bufferSize:format:)`.
///
/// The tap is not a real-time delivery mechanism. Its `bufferSize` argument is
/// advisory, and on macOS AVAudioEngine ignores small requests outright:
/// asking for 512 frames against a 512-frame hardware buffer yields **4410**
/// frames — a tenth of a second — delivered ten times a second. Everything fed
/// from the tap therefore inherits 100ms of chunking before anything
/// downstream gets a chance to add its own. That single fact dominated the
/// monitoring latency on the two-device path, and it also made pitch detection
/// a tenth of a second stale.
///
/// A sink node is called like any other render callback, at the hardware block
/// size. The same real-time rules apply as in `MonitorRenderer`: no allocation,
/// no locks, no blocking.
final class CaptureSink {
    let node: AVAudioSinkNode

    /// - Parameter monitorRing: nil on the duplex path, where monitoring is a
    ///   direct connection in the render graph and nothing needs buffering.
    /// - Parameter chordRing: its own ring rather than a second reader on
    ///   `analysisRing` — `RingBuffer` is strictly single-consumer. Written
    ///   unconditionally, same as `monitorRing`; `ChordAnalysisWorker` is
    ///   what decides whether anything is actually draining it, so an idle
    ///   Notes-mode session costs one more `write` call per render block,
    ///   not a second detector running.
    /// - Parameter recordingRing: its own ring for the same reason. Optional,
    ///   and nil in Release: the sample-capture screen is a maintainer tool
    ///   compiled out of shipping builds, so a shipped app writes the three
    ///   rings it always did and carries no cost for a feature nobody can
    ///   reach.
    init(analysisRing: RingBuffer, monitorRing: RingBuffer?, chordRing: RingBuffer, recordingRing: RingBuffer?) {
        node = AVAudioSinkNode { _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
            // Channel 0 of a deinterleaved capture. Multi-channel interfaces
            // expose their other inputs in the remaining buffers; the pitch
            // detector has always read the first alone.
            guard let source = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let captureTime = mach_absolute_time()
            let count = Int(frameCount)
            analysisRing.write(source, count: count, captureTime: captureTime)
            monitorRing?.write(source, count: count, captureTime: captureTime)
            chordRing.write(source, count: count, captureTime: captureTime)
            recordingRing?.write(source, count: count, captureTime: captureTime)
            return noErr
        }
    }
}
