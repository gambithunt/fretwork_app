import AVFoundation
import XCTest
@testable import Fretwork

/// The monitor slider moved off `mainMixerNode.outputVolume` and onto the
/// monitor leg's own gain stage, so sample playback can join the same mixer
/// without the slider governing it.
///
/// The first attempt at that move applied the level through a conditional cast
/// to `AVAudioMixing`, which `AVAudioUnitEQ` does not conform to. It compiled,
/// it ran, and the slider silently stopped doing anything — nothing in a build
/// log or a diff would have shown it. These tests render the graph offline and
/// assert on the samples that come out, which is the only thing that actually
/// proves a level was applied.
final class MonitorLevelTests: XCTestCase {
    private let rate = 44_100.0

    /// The monitor leg both `startDuplex` and `startSplit` build: a source, the
    /// bypassed-band EQ used purely as a gain stage, and the main mixer at
    /// unity. Rendered manually so no hardware is involved.
    private func renderPeak(gainDB: Float, sourceAmplitude: Float) throws -> Float {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!

        let phase = PhaseBox()
        let increment = 2.0 * .pi * 440.0 / rate
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let destination = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for frame in 0..<Int(frameCount) {
                destination[frame] = sourceAmplitude * Float(sin(phase.value))
                phase.value += increment
            }
            return noErr
        }

        let gain = AVAudioUnitEQ(numberOfBands: 1)
        gain.bands[0].bypass = true
        gain.globalGain = gainDB

        engine.attach(source)
        engine.attach(gain)
        engine.connect(source, to: gain, format: format)
        engine.connect(gain, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        defer { engine.stop() }

        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var peak: Float = 0
        // Ignore the first block: a fresh graph can emit a partial or silent
        // one before it settles, which would read as an attenuation that is
        // not there.
        for block in 0..<4 {
            let status = try engine.renderOffline(4096, to: buffer)
            XCTAssertEqual(status, .success)
            guard block > 0, let channel = buffer.floatChannelData?[0] else { continue }
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(channel[frame]))
            }
        }
        return peak
    }

    /// `AVAudioUnitEQ` genuinely cannot carry a per-input-bus level. This is
    /// the fact that sent the level to `globalGain` instead, and it is worth
    /// pinning: if a future SDK adds the conformance, the cheaper placement
    /// becomes available again.
    func testTheGainStageStillCannotCarryAPerBusLevel() {
        let gain = AVAudioUnitEQ(numberOfBands: 1)
        XCTAssertNil(gain as? AVAudioMixing, "AVAudioUnitEQ now conforms to AVAudioMixing — the per-bus level is available and is cheaper than globalGain")
        XCTAssertNotNil(AVAudioSourceNode(renderBlock: { _, _, _, _ in noErr }) as? AVAudioMixing, "AVAudioSourceNode must conform: the sample player relies on it for its own level")
    }

    // MARK: - The mapping

    func testFullVolumeIsTheFixedMakeupGainAlone() {
        XCTAssertEqual(AudioEngine.monitorGainDBForTesting(1), 4, accuracy: 0.001)
    }

    /// Half amplitude is -6.02 dB, on top of the +4 dB makeup — the same
    /// product the slider produced when it drove the mixer's output volume.
    func testHalfVolumeIsSixDBDownFromThat() {
        XCTAssertEqual(AudioEngine.monitorGainDBForTesting(0.5), 4 - 6.0206, accuracy: 0.01)
    }

    func testZeroVolumeIsTheSilenceFloorRatherThanNegativeInfinity() {
        let gain = AudioEngine.monitorGainDBForTesting(0)
        XCTAssertEqual(gain, -96, accuracy: 0.001)
        XCTAssertTrue(gain.isFinite, "a -inf globalGain would be rejected by the node")
    }

    /// Below the floor the mapping must clamp rather than run away: log10 of a
    /// very small slider value is a large negative number.
    func testVeryQuietClampsToTheFloor() {
        XCTAssertEqual(AudioEngine.monitorGainDBForTesting(0.0000001), -96, accuracy: 0.001)
    }

    // MARK: - What the graph actually renders

    /// Asserted against a unity render of the same graph rather than against
    /// absolute amplitudes. `mainMixerNode` applies an equal-power pan law to a
    /// mono input — measured at exactly 1/sqrt(2), see the test below — and
    /// baking that constant into an expected level would be asserting on the
    /// mixer's panning rather than on the slider's mapping.
    func testTheMappingScalesTheRenderedSignal() throws {
        let unity = try renderPeak(gainDB: 0, sourceAmplitude: 0.25)
        let full = try renderPeak(gainDB: AudioEngine.monitorGainDBForTesting(1), sourceAmplitude: 0.25)
        let half = try renderPeak(gainDB: AudioEngine.monitorGainDBForTesting(0.5), sourceAmplitude: 0.25)

        // +4dB of makeup at the top of the slider's travel.
        XCTAssertEqual(full / unity, 1.5849, accuracy: 0.01)
        // and half the slider is half the amplitude, exactly.
        XCTAssertEqual(half / full, 0.5, accuracy: 0.005)
    }

    /// Not a property of this change — it was true while the slider drove
    /// `outputVolume` too — but it is the reason a rendered monitor level does
    /// not equal the number on the slider, which is confusing enough to pin.
    func testTheMainMixerPansMonoInputDownThreeDB() throws {
        let unity = try renderPeak(gainDB: 0, sourceAmplitude: 0.25)
        XCTAssertEqual(unity, 0.25 / Float(2).squareRoot(), accuracy: 0.001)
    }

    /// Mute is attenuation to the node's floor, not a disconnect. Pinning what
    /// that floor actually renders as, rather than trusting the docstring:
    /// anything at or below -90 dBFS is inaudible through any real output, but
    /// it is not the exact zero the old `outputVolume = 0` produced.
    func testMuteRendersFarBelowAudibility() throws {
        let muted = try renderPeak(gainDB: AudioEngine.monitorGainDBForTesting(0), sourceAmplitude: 0.5)
        let dBFS = 20 * log10(max(muted, .leastNormalMagnitude))
        XCTAssertLessThan(dBFS, -90, "monitor mute rendered at \(dBFS) dBFS")
    }
}

/// The render block is `@Sendable` and runs on the audio thread; the test only
/// reads the phase from inside that block.
private final class PhaseBox: @unchecked Sendable {
    var value = 0.0
}
