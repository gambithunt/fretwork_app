import AVFoundation
import Darwin

/// Supplies the monitor signal from inside the playback graph's own render
/// callback, replacing a thread that polled a ring buffer on a 2ms sleep and
/// pushed `AVAudioPCMBuffer`s into an `AVAudioPlayerNode` queue.
///
/// That polling design forced a deep queue — roughly 46ms of scheduled audio —
/// purely to cover its own wake granularity, and it allocated a buffer per
/// block. Pulling instead of pushing removes both: the render callback asks for
/// exactly the frames the output device is about to play, at the moment it
/// needs them, so the only audio held in reserve is the ring backlog needed to
/// bridge two unsynchronised device clocks.
///
/// The render block is a real-time context. It does not allocate, lock, or
/// block — the same discipline any audio plugin's `process()` follows, and the
/// reason all sizing happens here in `init` rather than per call.
final class MonitorRenderer {
    let node: AVAudioSourceNode

    /// Render-thread-only state. Boxed rather than held on `self` so the render
    /// block never captures the owner, and never touches a Swift property whose
    /// access could be instrumented or made atomic behind our back.
    private final class Priming: @unchecked Sendable { var isPrimed = false }

    /// - Parameters:
    ///   - targetBacklogFrames: how much captured audio to keep in reserve. The
    ///     capture and playback callbacks fire on independent clocks with an
    ///     arbitrary phase relationship, so the reserve has to cover a whole
    ///     capture period plus jitter or the output side will regularly ask for
    ///     audio that has not been captured yet.
    ///   - trimThresholdFrames: the ceiling that bounds clock drift. It sits
    ///     well clear of the working range, because trimming discards samples
    ///     and a trim on ordinary jitter is heard as a tick.
    init(ring: RingBuffer, format: AVAudioFormat, targetBacklogFrames: Int, trimThresholdFrames: Int) {
        let priming = Priming()
        node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let wanted = Int(frameCount)
            guard let destination = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                isSilence.pointee = true
                return noErr
            }

            // Starting to play the instant the first sample lands would leave
            // the backlog hovering at zero, underrunning on every phase
            // wobble. Hold silence until there is a reserve to draw down.
            if !priming.isPrimed {
                guard ring.backlogFrames() >= targetBacklogFrames else {
                    memset(destination, 0, wanted * MemoryLayout<Float>.size)
                    isSilence.pointee = true
                    return noErr
                }
                priming.isPrimed = true
            }

            let filled = ring.readPartial(into: destination, count: wanted)
            if filled < wanted {
                memset(destination + filled, 0, (wanted - filled) * MemoryLayout<Float>.size)
                if filled == 0 { isSilence.pointee = true }
                // The reserve is spent. Rebuild it rather than limping along
                // underrunning on every subsequent block.
                priming.isPrimed = false
            }

            // Two hardware clocks are never exactly equal, so without a ceiling
            // the backlog — and the delay with it — grows for as long as the
            // stream runs.
            ring.trimBacklog(toAtMost: trimThresholdFrames)
            return noErr
        }
    }
}
