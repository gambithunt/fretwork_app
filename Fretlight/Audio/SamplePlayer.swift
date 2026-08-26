import AVFoundation
import Darwin
import Foundation

/// Plays the recorded note library out of whichever engine owns the output
/// device, polyphonically, without disturbing the monitor path.
///
/// One `AVAudioSourceNode` mixes a fixed pool of voices, in the same pulling
/// shape `MonitorRenderer` uses — see `AudioEngine`'s docstring for why pulling
/// replaced pushing into an `AVAudioPlayerNode` queue.
///
/// **The render block does not allocate, lock or block.** Voices live in a
/// preallocated array; note-ons arrive through a lock-free single-producer
/// queue; the library's audio is decoded up front into one stable block. What
/// the block does per frame is a linear interpolation and a multiply-add —
/// arithmetic, not resampling in the sense that rule is about. Playing back at
/// a ratio is how a sampler covers a 44.1 kHz library on a 48 kHz graph, a
/// non-standard tuning's pitch shift, and per-note detune, all with the same
/// three lines and no second copy of the audio.
final class SamplePlayer: @unchecked Sendable {
    /// Matches the web app's `VOICE_COUNT`, for the reason recorded there: more
    /// voices than strings so a fast sequence cannot reuse a voice before its
    /// previous note has rung out, which clips the tail.
    static let voiceCount = 10

    /// How quickly a note already sounding on a string is silenced when a new
    /// one is played on it. A real guitar does the same thing — a string can
    /// only sound one note — and doing it instantly is a click, so this is a
    /// fade rather than a stop. 8 ms is under a fretting hand's own transition
    /// and long enough that the discontinuity is inaudible.
    static let stringStealFadeSeconds = 0.008

    /// One playing note. A value type in a preallocated array: the render block
    /// mutates these in place and never allocates.
    private struct Voice {
        var audio: UnsafePointer<Float>?
        var frameCount = 0
        /// Fractional read position, advanced by `rate` each output frame.
        var position = 0.0
        var rate = 1.0
        var gain: Float = 0
        /// Which string this note is on, so a later note on the same string can
        /// find and release it. -1 when free.
        var string = -1
        /// Counts down while releasing; 0 means either free or sounding.
        var fadeFramesRemaining = 0
        var fadeFramesTotal = 0
        /// Monotonic, so voice stealing can pick the genuinely oldest note.
        var startedAt: UInt64 = 0
        var active = false
    }

    /// A note-on handed from a control thread to the render thread.
    private struct NoteOn {
        var audio: UnsafePointer<Float>?
        var frameCount = 0
        var rate = 1.0
        var gain: Float = 1
        var string = -1
    }

    /// Lock-free SPSC queue of pending note-ons, following `RingBuffer`'s
    /// approach: OSAtomic barriers rather than a mutex, because the consumer is
    /// the render thread. Sized well above any plausible burst — a six-string
    /// strum is six — so a full queue means something is wrong rather than
    /// merely busy.
    private final class CommandQueue: @unchecked Sendable {
        private let capacity = 64
        private var commands: UnsafeMutablePointer<NoteOn>
        private var writeIndex: Int32 = 0
        private var readIndex: Int32 = 0

        init() {
            commands = .allocate(capacity: capacity)
            commands.initialize(repeating: NoteOn(), count: capacity)
        }

        deinit {
            commands.deinitialize(count: capacity)
            commands.deallocate()
        }

        /// Producer side. Drops rather than blocks if the render thread has
        /// somehow stopped draining: a dropped note is better than a stalled
        /// control queue.
        @discardableResult
        func push(_ command: NoteOn) -> Bool {
            let write = Int(OSAtomicAdd32Barrier(0, &writeIndex))
            let read = Int(OSAtomicAdd32Barrier(0, &readIndex))
            guard write - read < capacity else { return false }
            commands[write % capacity] = command
            OSAtomicAdd32Barrier(1, &writeIndex)
            return true
        }

        /// Consumer side, render thread only.
        func pop() -> NoteOn? {
            let read = Int(OSAtomicAdd32Barrier(0, &readIndex))
            let write = Int(OSAtomicAdd32Barrier(0, &writeIndex))
            guard write - read > 0 else { return nil }
            let command = commands[read % capacity]
            OSAtomicAdd32Barrier(1, &readIndex)
            return command
        }
    }

    /// Render-thread-only state, boxed so the render block never captures the
    /// owner — the same reasoning as `MonitorRenderer.Priming`.
    private final class VoicePool: @unchecked Sendable {
        var voices: UnsafeMutablePointer<Voice>
        let count: Int
        var clock: UInt64 = 0
        /// Set by the control thread, read by the render thread. A plain flag:
        /// a torn read costs at most one block of the wrong state.
        var stopAllRequested: Int32 = 0

        init(count: Int) {
            self.count = count
            voices = .allocate(capacity: count)
            voices.initialize(repeating: Voice(), count: count)
        }

        deinit {
            voices.deinitialize(count: count)
            voices.deallocate()
        }
    }

    let node: AVAudioSourceNode
    /// The graph's rate, which every playback ratio is relative to.
    let sampleRate: Double
    /// Held so the audio the render block points into stays alive.
    private let library: NoteSampleLibrary
    private let queue = CommandQueue()
    private let pool = VoicePool(count: SamplePlayer.voiceCount)

    /// - Parameter format: the format of the leg this node feeds. Mono: the
    ///   library is mono, and the shared mixer downmixes to the device's layout
    ///   exactly as it does for the monitor leg.
    init(library: NoteSampleLibrary, format: AVAudioFormat) {
        self.library = library
        self.sampleRate = format.sampleRate
        let pool = self.pool
        let queue = self.queue
        let fadeFrames = max(1, Int(format.sampleRate * SamplePlayer.stringStealFadeSeconds))

        node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let wanted = Int(frameCount)
            guard let destination = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                isSilence.pointee = true
                return noErr
            }
            memset(destination, 0, wanted * MemoryLayout<Float>.size)

            if OSAtomicCompareAndSwap32Barrier(1, 0, &pool.stopAllRequested) {
                for index in 0..<pool.count where pool.voices[index].active {
                    // Release rather than cut: stop() is a user-visible action
                    // and a click is the one thing it must not produce.
                    Self.beginRelease(&pool.voices[index], frames: fadeFrames)
                }
            }

            while let command = queue.pop() {
                Self.start(command, in: pool, fadeFrames: fadeFrames)
            }

            var sounded = false
            for index in 0..<pool.count {
                guard pool.voices[index].active else { continue }
                sounded = true
                Self.render(&pool.voices[index], into: destination, frames: wanted)
            }
            if !sounded { isSilence.pointee = true }
            return noErr
        }
    }

    // MARK: - Render-thread helpers
    //
    // Static and taking `inout Voice` so none of them can capture `self` into
    // the render block.

    private static func beginRelease(_ voice: inout Voice, frames: Int) {
        guard voice.active, voice.fadeFramesRemaining == 0 else { return }
        voice.fadeFramesTotal = frames
        voice.fadeFramesRemaining = frames
    }

    private static func start(_ command: NoteOn, in pool: VoicePool, fadeFrames: Int) {
        guard let audio = command.audio, command.frameCount > 0 else { return }

        // A string can only sound one note. Release whatever is on this one.
        for index in 0..<pool.count where pool.voices[index].active && pool.voices[index].string == command.string {
            beginRelease(&pool.voices[index], frames: fadeFrames)
        }

        pool.clock &+= 1
        let slot = freeSlot(in: pool) ?? oldestSlot(in: pool)
        pool.voices[slot] = Voice(
            audio: audio,
            frameCount: command.frameCount,
            position: 0,
            rate: command.rate,
            gain: command.gain,
            string: command.string,
            fadeFramesRemaining: 0,
            fadeFramesTotal: 0,
            startedAt: pool.clock,
            active: true
        )
    }

    private static func freeSlot(in pool: VoicePool) -> Int? {
        for index in 0..<pool.count where !pool.voices[index].active { return index }
        return nil
    }

    /// Voice exhaustion degrades by taking the oldest note, never by allocating
    /// a new voice. Releasing voices go first — they are already on their way
    /// out, so taking one costs less of a real note than taking a sounding one.
    private static func oldestSlot(in pool: VoicePool) -> Int {
        var best = 0
        var bestKey = (releasing: false, age: UInt64.max)
        for index in 0..<pool.count {
            let voice = pool.voices[index]
            let key = (releasing: voice.fadeFramesRemaining > 0, age: voice.startedAt)
            if !bestKey.releasing && key.releasing {
                best = index
                bestKey = key
            } else if bestKey.releasing == key.releasing && key.age < bestKey.age {
                best = index
                bestKey = key
            }
        }
        return best
    }

    /// Mixes one voice into `destination`. Linear interpolation: the library is
    /// 44.1 kHz and the graph may not be, and a note may be detuned or shifted
    /// for a non-standard tuning, so the read position is fractional.
    private static func render(_ voice: inout Voice, into destination: UnsafeMutablePointer<Float>, frames: Int) {
        guard let audio = voice.audio else {
            voice.active = false
            return
        }
        for frame in 0..<frames {
            let index = Int(voice.position)
            guard index + 1 < voice.frameCount else {
                voice.active = false
                voice.string = -1
                return
            }
            let fraction = Float(voice.position - Double(index))
            let value = audio[index] + (audio[index + 1] - audio[index]) * fraction

            var gain = voice.gain
            if voice.fadeFramesRemaining > 0 {
                gain *= Float(voice.fadeFramesRemaining) / Float(voice.fadeFramesTotal)
                voice.fadeFramesRemaining -= 1
                if voice.fadeFramesRemaining == 0 {
                    destination[frame] += value * gain
                    voice.active = false
                    voice.string = -1
                    return
                }
            }
            destination[frame] += value * gain
            voice.position += voice.rate
        }
    }

    // MARK: - Control

    /// Sounds one position. Safe to call from any thread; the note starts at
    /// the next render block.
    ///
    /// - Parameters:
    ///   - rateMultiplier: pitch shift as a frequency ratio, on top of the
    ///     library-to-graph rate conversion. 1 plays the take as recorded.
    ///   - gain: 0...1 on top of the player's own output level.
    @discardableResult
    func play(string: Int, fret: Int, rateMultiplier: Double = 1, gain: Float = 1) -> Bool {
        guard let sample = library.sample(string: string, fret: fret) else { return false }
        return queue.push(NoteOn(
            audio: library.audio(for: sample),
            frameCount: sample.frameCount,
            rate: sample.sampleRate / sampleRate * rateMultiplier,
            gain: gain,
            string: string
        ))
    }

    /// Releases every sounding voice. Not a hard stop: the fade is the same one
    /// voice stealing uses, so cancelling a sequence cannot click.
    func stopAll() {
        OSAtomicCompareAndSwap32Barrier(0, 1, &pool.stopAllRequested)
    }

    /// How many voices are sounding. For tests and diagnostics — reading this
    /// races the render thread by design, which is why nothing in the audio
    /// path consults it.
    var activeVoiceCount: Int {
        (0..<pool.count).reduce(into: 0) { $0 += pool.voices[$1].active ? 1 : 0 }
    }
}
