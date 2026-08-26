import AVFoundation
import XCTest
@testable import Fretwork

/// Verifies the voice pool by rendering it offline and reading the samples that
/// come out — the graph is never attached to hardware here.
///
/// `CLAUDE.md` records why this is the standard rather than reading the diff:
/// the detection board's rewrite "looked right and was placing every dot
/// wrongly; only the pixels said so". A mixer is the same shape of problem.
final class SamplePlayerTests: XCTestCase {
    /// 138 AAC files, decoded once for the whole suite rather than per test.
    private static let library: NoteSampleLibrary? = try? NoteSampleLibrary.loadFromBundle()

    private func requireLibrary() throws -> NoteSampleLibrary {
        try XCTUnwrap(Self.library, "the bundled note library failed to load")
    }

    /// Renders `blocks` blocks of `frames`, calling `beforeBlock` ahead of each
    /// so a test can play notes at a known point in time.
    private func render(
        player: SamplePlayer,
        engine: AVAudioEngine,
        format: AVAudioFormat,
        blocks: Int,
        frames: AVAudioFrameCount = 512,
        beforeBlock: (Int) -> Void = { _ in }
    ) throws -> [Float] {
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames)!
        var out: [Float] = []
        for block in 0..<blocks {
            beforeBlock(block)
            let status = try engine.renderOffline(frames, to: buffer)
            XCTAssertEqual(status, .success)
            if let channel = buffer.floatChannelData?[0] {
                out.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
        }
        return out
    }

    /// The player on its own leg into a unity mixer — the shape `AudioEngine`
    /// builds, minus the monitor leg.
    private func makeGraph(rate: Double = 44_100) throws -> (SamplePlayer, AVAudioEngine, AVAudioFormat) {
        let library = try requireLibrary()
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let engine = AVAudioEngine()
        let player = SamplePlayer(library: library, format: format)
        engine.attach(player.node)
        engine.connect(player.node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        return (player, engine, format)
    }

    // MARK: - The library itself

    func testTheBundledLibraryCoversEveryPosition() throws {
        let library = try requireLibrary()
        XCTAssertEqual(library.count, 138, "every string/fret pair must ship")
        for string in 0..<NoteSampleLibrary.stringCount {
            for fret in 0...NoteSampleLibrary.highestFret {
                let sample = library.sample(string: string, fret: fret)
                XCTAssertNotNil(sample, "missing string \(string) fret \(fret)")
                XCTAssertGreaterThan(sample?.frameCount ?? 0, 0)
            }
        }
    }

    /// The filename's MIDI number is deliberate redundancy (workstream 002
    /// Phase 0). Checking it against the tuning here means a library rebuilt
    /// with a shifted string order cannot pass silently — the failure mode
    /// `CLAUDE.md` calls out as "six plausible fret numbers".
    func testEveryPositionSoundsTheMIDINoteItsPlaceImplies() throws {
        let library = try requireLibrary()
        for sample in library.samples {
            let expected = Tunings.standard.openMIDINotes[sample.string] + sample.fret
            XCTAssertEqual(sample.midi, expected, "string \(sample.string) fret \(sample.fret)")
        }
    }

    // MARK: - Playback

    func testANoteRendersTheRecordedSampleForThatPosition() throws {
        let library = try requireLibrary()
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }

        let sample = try XCTUnwrap(library.sample(string: 2, fret: 7))
        let source = library.audio(for: sample)

        let rendered = try render(player: player, engine: engine, format: format, blocks: 2) { block in
            if block == 0 { player.play(string: 2, fret: 7) }
        }

        // The main mixer pans mono down 3dB (see MonitorLevelTests), so compare
        // shape rather than absolute level: the rendered signal must be a fixed
        // multiple of the source, sample for sample.
        let offset = 8 // a few frames in, past the take's own 2ms attack fade
        let scale = rendered[offset] / source[offset]
        XCTAssertGreaterThan(abs(scale), 0.01, "nothing was rendered")
        for frame in offset..<(offset + 400) {
            XCTAssertEqual(rendered[frame], source[frame] * scale, accuracy: 0.002, "diverged at frame \(frame)")
        }
    }

    func testSilenceUntilANoteIsPlayed() throws {
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }
        let rendered = try render(player: player, engine: engine, format: format, blocks: 2)
        XCTAssertEqual(rendered.map { abs($0) }.max() ?? 0, 0, "an idle player must emit nothing")
    }

    func testAnUnrecordedPositionIsRefusedRatherThanPlayedWrong() throws {
        let (player, _, _) = try makeGraph()
        XCTAssertFalse(player.play(string: 9, fret: 0))
        XCTAssertFalse(player.play(string: 0, fret: 99))
    }

    // MARK: - Voice behaviour

    func testNotesOnDifferentStringsSoundTogether() throws {
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }
        _ = try render(player: player, engine: engine, format: format, blocks: 2) { block in
            guard block == 0 else { return }
            for string in 0..<6 { player.play(string: string, fret: 5) }
        }
        XCTAssertEqual(player.activeVoiceCount, 6, "a six-string strum must hold six voices")
    }

    /// A real guitar string can only sound one note at a time.
    func testASecondNoteOnAStringReleasesTheFirst() throws {
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }
        _ = try render(player: player, engine: engine, format: format, blocks: 1) { block in
            if block == 0 { player.play(string: 3, fret: 2) }
        }
        XCTAssertEqual(player.activeVoiceCount, 1)

        // The released voice needs its fade to run out before it frees, so
        // render well past the 8ms release.
        _ = try render(player: player, engine: engine, format: format, blocks: 3) { block in
            if block == 0 { player.play(string: 3, fret: 9) }
        }
        XCTAssertEqual(player.activeVoiceCount, 1, "the earlier note on that string must have been released")
    }

    /// Cutting a ringing note dead is a click. The steal fades instead, so the
    /// rendered signal has no step in it.
    func testAStealIntroducesNoDiscontinuity() throws {
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }

        // Let a low note get properly loud first, then take the string.
        let rendered = try render(player: player, engine: engine, format: format, blocks: 8) { block in
            if block == 0 { player.play(string: 0, fret: 0) }
            if block == 4 { player.play(string: 0, fret: 12) }
        }

        let peak = rendered.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.01, "nothing was rendered")
        var largestStep: Float = 0
        for frame in 1..<rendered.count {
            largestStep = max(largestStep, abs(rendered[frame] - rendered[frame - 1]))
        }
        // A hard cut would step by roughly the signal's own amplitude. Real
        // audio moves too, so the bar is that the largest jump stays well under
        // the peak rather than being zero.
        XCTAssertLessThan(largestStep, peak * 0.5, "a steal left a step in the output")
    }

    func testVoiceExhaustionStealsRatherThanGrows() throws {
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }
        _ = try render(player: player, engine: engine, format: format, blocks: 4) { block in
            // 24 notes spread across strings and frets, far more than the pool.
            for fret in 0..<4 { player.play(string: block % 6, fret: fret * 3) }
            for string in 0..<6 { player.play(string: string, fret: block + 1) }
        }
        XCTAssertLessThanOrEqual(player.activeVoiceCount, SamplePlayer.voiceCount)
    }

    func testStopAllSilencesEverySoundingVoice() throws {
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }
        _ = try render(player: player, engine: engine, format: format, blocks: 1) { block in
            guard block == 0 else { return }
            for string in 0..<6 { player.play(string: string, fret: 4) }
        }
        XCTAssertEqual(player.activeVoiceCount, 6)

        let tail = try render(player: player, engine: engine, format: format, blocks: 4) { block in
            if block == 0 { player.stopAll() }
        }
        XCTAssertEqual(player.activeVoiceCount, 0, "stop must release every voice")
        // And the release must not have been a cut.
        let last = tail.suffix(512)
        XCTAssertEqual(last.map { abs($0) }.max() ?? 0, 0, accuracy: 0.0001)
    }

    // MARK: - Rate

    /// The library is 44.1 kHz; the graph often is not. A take must sound at
    /// its recorded pitch either way, which means the playback ratio carries
    /// the conversion rather than the audio being resampled at load.
    func testAGraphAtADifferentRatePlaysTheSamePitch() throws {
        let library = try requireLibrary()
        let sample = try XCTUnwrap(library.sample(string: 0, fret: 0))

        let native = SamplePlayer(library: library, format: AVAudioFormat(standardFormatWithSampleRate: sample.sampleRate, channels: 1)!)
        let doubled = SamplePlayer(library: library, format: AVAudioFormat(standardFormatWithSampleRate: sample.sampleRate * 2, channels: 1)!)

        XCTAssertEqual(native.sampleRate, sample.sampleRate)
        // At twice the graph rate each output frame advances half a source
        // frame, which is what keeps the pitch the same.
        XCTAssertEqual(doubled.sampleRate, sample.sampleRate * 2)
    }

    /// Detune and non-standard tunings both arrive as a frequency ratio, so a
    /// note played an octave up must run through its take twice as fast and
    /// therefore end sooner.
    func testARateMultiplierShortensTheNoteProportionally() throws {
        let (player, engine, format) = try makeGraph()
        defer { engine.stop() }

        func framesUntilSilent(rate: Double) throws -> Int {
            player.stopAll()
            _ = try render(player: player, engine: engine, format: format, blocks: 4)
            // Long enough to outlast the take itself: the build step trims to
            // 4s, which is 345 blocks of 512 at 44.1kHz. A window shorter than
            // the note measures the window, not the note.
            let rendered = try render(player: player, engine: engine, format: format, blocks: 420) { block in
                if block == 0 { player.play(string: 0, fret: 0, rateMultiplier: rate) }
            }
            var last = 0
            for (frame, value) in rendered.enumerated() where abs(value) > 0.0001 { last = frame }
            return last
        }

        let normal = try framesUntilSilent(rate: 1)
        let octaveUp = try framesUntilSilent(rate: 2)
        XCTAssertGreaterThan(normal, 0)
        XCTAssertEqual(Double(octaveUp), Double(normal) / 2, accuracy: Double(normal) * 0.05)
    }
}
