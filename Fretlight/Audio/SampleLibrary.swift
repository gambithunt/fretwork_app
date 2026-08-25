#if DEBUG
import AVFoundation
import Darwin
import Foundation

/// One recorded position, as the manifest records it.
struct SampleLibraryEntry: Codable, Sendable, Equatable {
    let string: Int
    let fret: Int
    let targetMIDI: Int
    let detectedFrequency: Double
    let centsDeviation: Double
    let peak: Float
    let frameCount: Int
    let sampleRate: Double
    let recordedAt: Date
    /// Accepted, but its level sits well off the session's median. Recorded so
    /// attack consistency can be reviewed rather than silently drifting as an
    /// hour-long session wears on.
    let peakFlagged: Bool
}

/// A disagreement between the manifest and what is actually on disk.
enum SampleLibraryIssue: Sendable, Equatable {
    case missingAudio(string: Int, fret: Int)
    case untrackedAudio(filename: String)
}

/// The on-disk note-sample library: the audio files and the manifest that
/// describes them.
///
/// Takes its directory rather than choosing one — where the library lives is
/// the capture screen's decision, not this type's.
final class SampleLibrary {
    /// Six strings, frets 0 through 22.
    static let stringCount = 6
    static let highestFret = 22

    /// How far a take's peak may sit from the running median before it is
    /// flagged. Generous, because picking force genuinely varies and the point
    /// is to catch drift, not to police every stroke.
    static let peakDeviationRatio: Float = 0.35

    private let directory: URL
    private let manifestURL: URL

    init(directory: URL) {
        self.directory = directory
        manifestURL = directory.appendingPathComponent("manifest.json")
    }

    /// `s{string}-f{fret:02}-m{midi:03}.wav`, string 0 = Low E. The MIDI
    /// number is redundant with string and fret, deliberately: it lets a later
    /// build step cross-check a filename against the manifest's detected pitch
    /// and catch a transcription error.
    static func filename(string: Int, fret: Int) -> String? {
        guard Tunings.standard.openMIDINotes.indices.contains(string), (0...highestFret).contains(fret) else { return nil }
        return String(format: "s%d-f%02d-m%03d.wav", string, fret, Tunings.standard.openMIDINotes[string] + fret)
    }

    static var expectedPositions: [FretPosition] {
        (0..<stringCount).flatMap { string in
            (0...highestFret).map { FretPosition(string: string, fret: $0) }
        }
    }

    func entries() throws -> [SampleLibraryEntry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return try JSONDecoder().decode([SampleLibraryEntry].self, from: data)
    }

    /// What is still to record. A session runs to 138 takes, so it has to be
    /// resumable across several sittings.
    func missingPositions() throws -> [FretPosition] {
        let recorded = Set(try entries().map { FretPosition(string: $0.string, fret: $0.fret) })
        return Self.expectedPositions.filter { !recorded.contains($0) }
    }

    /// Writes one take, replacing that position if it was already recorded and
    /// leaving every other position untouched.
    ///
    /// **Crash consistency.** Two files cannot be replaced in one atomic step
    /// on this filesystem, so the ordering is chosen to make the surviving
    /// failure mode the harmless one: the audio is put in place first, then
    /// the manifest is replaced atomically. A crash in between leaves an
    /// audio file no manifest row mentions — which `reconcile()` reports and
    /// re-recording overwrites. The opposite order would leave a row claiming
    /// a sample that does not exist, which the library build step would trust.
    /// - Parameter rawPeak: how loud the take was *as played*, before
    ///   normalisation. Defaults to the take's own peak, which is right for a
    ///   take that has not been normalised. It matters because accepted takes
    ///   are normalised to a fixed level before they are written: recording
    ///   the normalised peak would store the same number every time and make
    ///   the consistency flag structurally incapable of firing, which is the
    ///   opposite of what it is for.
    @discardableResult
    func write(take: SampleRecorder.Take, string: Int, fret: Int, frequency: Double, cents: Double, rawPeak: Float? = nil) throws -> SampleLibraryEntry {
        let peakAsPlayed = rawPeak ?? take.peak
        guard let name = Self.filename(string: string, fret: fret) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var all = try entries()
        let entry = SampleLibraryEntry(
            string: string,
            fret: fret,
            targetMIDI: Tunings.standard.openMIDINotes[string] + fret,
            detectedFrequency: frequency,
            centsDeviation: cents,
            peak: peakAsPlayed,
            frameCount: take.samples.count,
            sampleRate: take.sampleRate,
            recordedAt: Date(),
            peakFlagged: isPeakOutlier(peakAsPlayed, against: all)
        )
        all.removeAll { $0.string == string && $0.fret == fret }
        all.append(entry)

        let staged = directory.appendingPathComponent(".staged-\(UUID().uuidString).wav")
        try writeWAV(take, to: staged)
        // `rename` replaces an existing destination atomically; `moveItem`
        // throws on one, and removing first would leave a window with no audio
        // at all.
        let destination = directory.appendingPathComponent(name)
        guard rename(staged.path, destination.path) == 0 else {
            try? FileManager.default.removeItem(at: staged)
            throw CocoaError(.fileWriteUnknown)
        }
        try JSONEncoder().encode(all).write(to: manifestURL, options: .atomic)
        return entry
    }

    /// Reports disagreements rather than repairing them — a missing sample is
    /// a prompt to re-record that position, not something to paper over.
    func reconcile() throws -> [SampleLibraryIssue] {
        let rows = try entries()
        let onDisk = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.filter { $0.hasSuffix(".wav") } ?? []
        )
        var tracked: Set<String> = []
        var issues: [SampleLibraryIssue] = []
        for row in rows {
            guard let name = Self.filename(string: row.string, fret: row.fret) else { continue }
            tracked.insert(name)
            if !onDisk.contains(name) {
                issues.append(.missingAudio(string: row.string, fret: row.fret))
            }
        }
        issues += onDisk.subtracting(tracked).sorted().map { .untrackedAudio(filename: $0) }
        return issues
    }

    private func isPeakOutlier(_ peak: Float, against entries: [SampleLibraryEntry]) -> Bool {
        let peaks = entries.map(\.peak).sorted()
        guard !peaks.isEmpty else { return false }
        let median = peaks[peaks.count / 2]
        guard median > 0 else { return false }
        return abs(peak - median) / median > Self.peakDeviationRatio
    }

    /// 24-bit PCM, mono, at the take's own rate. The buffer is float and the
    /// file is 24-bit integer; `AVAudioFile` converts on write.
    private func writeWAV(_ take: SampleRecorder.Take, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: take.sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(take.samples.count, 1)))
        else { throw CocoaError(.fileWriteUnknown) }

        buffer.frameLength = AVAudioFrameCount(take.samples.count)
        take.samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: take.samples.count)
        }

        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: take.sampleRate
        ])
        try file.write(from: buffer)
    }
}
#endif
