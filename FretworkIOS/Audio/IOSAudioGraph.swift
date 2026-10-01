import AVFoundation
import Foundation

/// Which legs an iOS graph is built with.
enum IOSAudioGraphLeg: Sendable, Equatable {
    /// Microphone capture (dead-ended into the analysis sink) plus the sample
    /// playback output path. Used while the player is listening.
    case captureAndOutput
    /// Sample playback only. `engine.inputNode` is never touched, so no
    /// microphone permission is requested and no mic session is opened — a
    /// module playing examples must not need the grant.
    case outputOnly
}

/// The iOS graph seam. Deliberately **not** `@MainActor`: the whole point of
/// the boundary is that `build`/`start`/`stop` (which touch `AVAudioEngine`,
/// `engine.inputNode` and `engine.start()`, any of which can stall on a bad
/// route) run off the main actor. Implementations are `Sendable` and serialize
/// their own state; the controller drives them from a private serial queue.
///
/// Realtime blocks are **not** built here. The capture sink is `CaptureSink`,
/// whose `AVAudioSinkNode` receiver block is created in its own nonisolated
/// `init`; the playback source node is `SamplePlayer`, likewise nonisolated.
/// A block written in an isolated context would carry an executor check and
/// trap on the first realtime callback (Phase 1, commit `e858416`), which is
/// why this seam reuses those two types instead of recreating them.
protocol IOSAudioGraphHandling: AnyObject, Sendable {
    var isRunning: Bool { get }
    /// The rate the graph's own nodes run at (the session rate it was built
    /// with). The player uses this.
    var sampleRate: Double { get }
    /// The rate the capture sink actually receives — the input node's format
    /// rate, read once the engine is up. This is what the pitch/chord workers
    /// must be told, because it is the rate of the samples in their rings.
    /// Nil for an output-only graph (no capture leg).
    var captureSampleRate: Double? { get }
    func start() throws
    func stop()
    /// Attaches a decoded player, connecting it to the output live if the
    /// graph is already running, otherwise remembering it for `start()`.
    func attachPlayer(_ player: SamplePlayer)
}

/// `Sendable` because it runs on a detached task: a slow `session.setActive`
/// or `engine.start()` must not block the main actor (the Mac `graphQueue`
/// lesson, iOS-shaped).
protocol IOSAudioGraphBuilding: Sendable {
    func build(leg: IOSAudioGraphLeg,
               sessionSampleRate: Double,
               analysisRing: RingBuffer,
               chordRing: RingBuffer) throws -> IOSAudioGraphHandling
}

/// Production builder. Stateless, so it is trivially `Sendable` without an
/// ownership proof.
struct SystemIOSAudioGraphBuilder: IOSAudioGraphBuilding {
    func build(leg: IOSAudioGraphLeg,
               sessionSampleRate: Double,
               analysisRing: RingBuffer,
               chordRing: RingBuffer) throws -> IOSAudioGraphHandling {
        try SystemIOSAudioGraph(
            leg: leg,
            sessionSampleRate: sessionSampleRate,
            analysisRing: analysisRing,
            chordRing: chordRing
        )
    }
}

enum IOSAudioGraphError: Error, Sendable, CustomStringConvertible {
    case unsupportedFormat(sampleRate: Double)
    case unsupportedInputFormat

    var description: String {
        switch self {
        case .unsupportedFormat(let sampleRate):
            "The iOS audio graph could not build a mono format at \(sampleRate) Hz."
        case .unsupportedInputFormat:
            "The microphone route did not expose a usable Float32 input format."
        }
    }
}

/// The one iOS `AVAudioEngine`: capture dead-ends into the sink and sample
/// playback feeds the output mixer. There is no edge from input to any output,
/// so C-03 ("no live monitoring") is structural rather than a runtime check.
///
/// **Ownership proof for `@unchecked Sendable`.** Every stored property is
/// either immutable after `init` or mutated only while `lock` is held; the only
/// code that runs without the lock is the realtime callback inside
/// `CaptureSink`/`SamplePlayer`, which touches only its own node's preallocated
/// state. `start`/`stop`/`attachPlayer` are therefore safe to call from the
/// controller's serial queue and from a later main-actor attach.
final class SystemIOSAudioGraph: IOSAudioGraphHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let leg: IOSAudioGraphLeg
    private let engine = AVAudioEngine()
    private let sink: CaptureSink?
    /// Mono at the graph rate; what the player node and the mixer use.
    private let graphFormat: AVAudioFormat
    private var player: SamplePlayer?
    private var running = false
    /// The input node's format rate, captured in `start()` once the engine is
    /// up. This — not the session rate the graph was *built* with — is the
    /// rate of the samples `CaptureSink` writes into the rings.
    private var inputSampleRate: Double?

    let sampleRate: Double

    init(leg: IOSAudioGraphLeg,
         sessionSampleRate: Double,
         analysisRing: RingBuffer,
         chordRing: RingBuffer) throws {
        self.leg = leg
        self.sampleRate = sessionSampleRate
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sessionSampleRate, channels: 1) else {
            throw IOSAudioGraphError.unsupportedFormat(sampleRate: sessionSampleRate)
        }
        self.graphFormat = mono
        // No monitor ring and no recording ring: iOS has no live monitoring
        // (C-03) and no sample-capture tool.
        self.sink = leg == .captureAndOutput
            ? CaptureSink(analysisRing: analysisRing, monitorRing: nil, chordRing: chordRing, recordingRing: nil)
            : nil
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    var captureSampleRate: Double? {
        lock.lock(); defer { lock.unlock() }
        return inputSampleRate
    }

    func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }

        if let sink {
            let input = engine.inputNode
            let hardware = input.outputFormat(forBus: 0)
            guard hardware.channelCount > 0, hardware.sampleRate > 0 else {
                throw IOSAudioGraphError.unsupportedInputFormat
            }
            // Mono is enforced at the connection: `AVAudioEngine` inserts the
            // channel conversion, and `CaptureSink` then reads channel 0 of the
            // mono deinterleaved buffer. R-1 in the design flags this as the
            // one unmeasured iOS conversion; the fallback (if a route ever
            // refuses it) is an iOS-only downmix sink, not a second graph.
            let captureFormat = hardware.channelCount == 1
                ? hardware
                : (AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: 1) ?? graphFormat)
            inputSampleRate = hardware.sampleRate
            engine.attach(sink.node)
            engine.connect(input, to: sink.node, format: captureFormat)
        }

        if let player {
            attachPlayerLocked(player)
        }

        // The mixer → output edge is always present so a player can join a
        // running graph later without a rebuild.
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running || sink != nil || player != nil else { return }
        engine.stop()
        if let sink {
            engine.disconnectNodeInput(sink.node)
            engine.detach(sink.node)
        }
        if let player {
            engine.disconnectNodeInput(player.node)
            engine.detach(player.node)
        }
        engine.reset()
        running = false
    }

    func attachPlayer(_ player: SamplePlayer) {
        lock.lock(); defer { lock.unlock() }
        self.player = player
        guard running else { return }
        attachPlayerLocked(player)
    }

    private func attachPlayerLocked(_ player: SamplePlayer) {
        engine.attach(player.node)
        engine.connect(player.node, to: engine.mainMixerNode, format: graphFormat)
        if !running {
            // Still true on the next `start()`; connecting here is harmless and
            // keeps the live-attach path identical.
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        }
    }
}
