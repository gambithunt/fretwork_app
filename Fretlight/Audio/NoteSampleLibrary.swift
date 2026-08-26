import AVFoundation
import Foundation

/// The recorded note library as it ships in the app bundle: one take per
/// position on the neck in standard tuning, decoded into memory so the render
/// thread can read it without touching a file.
///
/// Distinct from `SampleLibrary`, which is the *masters* library the capture
/// screen writes and which is compiled out of Release entirely. This one is
/// read-only, ships with the app, and is what workstream 003 plays from. The
/// two never meet: masters are 24-bit WAV plus a manifest of recording
/// evidence; this is trimmed, aligned, converted audio plus a compact index.
///
/// **The files land flat in `Contents/Resources`.** `Fretlight/` is a
/// `PBXFileSystemSynchronizedRootGroup`, so the repo's
/// `Fretlight/Resources/NoteSamples/` folder structure does not survive into
/// the bundle — every take is a bare filename beside everything else, and a
/// `subdirectory:` lookup finds nothing.
final class NoteSampleLibrary: @unchecked Sendable {
    /// One position's audio, as an offset into `storage`.
    struct Sample: Sendable {
        let string: Int
        let fret: Int
        let midi: Int
        /// Where this take starts in the shared storage block.
        let offset: Int
        let frameCount: Int
        /// The rate the take was recorded at. Playback divides by the graph's
        /// rate to get a playback ratio, so a 44.1 kHz library sounds correct
        /// through a 48 kHz graph without being resampled at load.
        let sampleRate: Double
    }

    /// What `scripts/build-sample-library.sh` writes alongside the audio.
    private struct Index: Decodable {
        struct Position: Decodable {
            let string: Int
            let fret: Int
            let targetMIDI: Int
            let filename: String
            let sampleRate: Double
            let frameCount: Int
        }
        let format: String
        let positions: [Position]
    }

    enum LoadError: Error, CustomStringConvertible {
        case indexMissing
        case indexUnreadable(String)
        case audioMissing(String)
        case audioUnreadable(String, String)
        case empty

        var description: String {
            switch self {
            case .indexMissing: "The bundled note library's index.json is missing."
            case .indexUnreadable(let why): "The bundled note library's index.json could not be read: \(why)"
            case .audioMissing(let name): "The bundled note library is missing \(name)."
            case .audioUnreadable(let name, let why): "The bundled note library's \(name) could not be decoded: \(why)"
            case .empty: "The bundled note library contains no positions."
            }
        }
    }

    /// All takes concatenated. One allocation for the whole library rather than
    /// 138, so the render thread reads from a single stable block and there is
    /// no per-voice ownership to reason about.
    private let storage: UnsafeMutablePointer<Float>
    private let storageCount: Int
    /// Indexed by `string * (highestFret + 1) + fret`, so a lookup on the audio
    /// thread is arithmetic rather than a dictionary hash.
    private let byPosition: [Sample?]

    static let stringCount = 6
    static let highestFret = 22
    private static var slotCount: Int { stringCount * (highestFret + 1) }

    private init(storage: UnsafeMutablePointer<Float>, storageCount: Int, byPosition: [Sample?]) {
        self.storage = storage
        self.storageCount = storageCount
        self.byPosition = byPosition
    }

    deinit {
        storage.deinitialize(count: storageCount)
        storage.deallocate()
    }

    /// Decodes the whole library. Slow — 138 files — so callers run it off the
    /// main actor and off any audio thread; nothing here may be called while
    /// the render block is reading.
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> NoteSampleLibrary {
        guard let indexURL = bundle.url(forResource: "index", withExtension: "json") else {
            throw LoadError.indexMissing
        }
        let index: Index
        do {
            index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        } catch {
            throw LoadError.indexUnreadable(error.localizedDescription)
        }
        guard !index.positions.isEmpty else { throw LoadError.empty }

        // Size the shared block from the index, then decode straight into it,
        // one file at a time. Decoding every take into its own array first and
        // copying afterwards held two full copies at once: measured at +175 MB
        // of RSS for an 85 MB library.
        //
        // The index's `frameCount` is a *claim* about a file, so it is never
        // trusted as the write length — each read is clamped to the space
        // actually reserved for it, and a file longer than its row is reported
        // rather than allowed to run past. `PitchDetector`'s scratch buffer is
        // in `CLAUDE.md` for exactly this mistake made the other way round:
        // sized by one quantity, written according to another.
        let claimed = index.positions.reduce(0) { $0 + max($1.frameCount, 0) }
        let capacity = max(claimed, 1)
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)

        var slots = [Sample?](repeating: nil, count: slotCount)
        var offset = 0
        for position in index.positions {
            let name = (position.filename as NSString).deletingPathExtension
            let ext = (position.filename as NSString).pathExtension
            guard let url = bundle.url(forResource: name, withExtension: ext) else {
                storage.deinitialize(count: capacity)
                storage.deallocate()
                throw LoadError.audioMissing(position.filename)
            }
            let reserved = max(position.frameCount, 0)
            do {
                let written = try readMono(url, into: storage + offset, capacity: reserved)
                if let slot = slotIndex(string: position.string, fret: position.fret) {
                    slots[slot] = Sample(
                        string: position.string,
                        fret: position.fret,
                        midi: position.targetMIDI,
                        offset: offset,
                        frameCount: written,
                        sampleRate: position.sampleRate
                    )
                }
            } catch {
                storage.deinitialize(count: capacity)
                storage.deallocate()
                throw LoadError.audioUnreadable(position.filename, error.localizedDescription)
            }
            offset += reserved
        }

        return NoteSampleLibrary(storage: storage, storageCount: capacity, byPosition: slots)
    }

    /// Decodes one file straight into `destination`, writing at most `capacity`
    /// frames and returning how many it wrote.
    ///
    /// A multi-channel file is summed rather than silently taking channel 0 —
    /// the build step rejects anything that is not mono upstream of here, so
    /// this is a belt-and-braces path, not an expected one.
    private static func readMono(
        _ url: URL,
        into destination: UnsafeMutablePointer<Float>,
        capacity: Int
    ) throws -> Int {
        guard capacity > 0 else { return 0 }
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return 0 }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            return 0
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return 0 }
        // The clamp, not the claim: a file longer than its index row fills the
        // space reserved for it and no more.
        let count = min(Int(buffer.frameLength), capacity)
        let channelCount = Int(buffer.format.channelCount)
        if channelCount == 1 {
            destination.update(from: channels[0], count: count)
        } else {
            let scale = 1 / Float(channelCount)
            for frame in 0..<count {
                var sum: Float = 0
                for channel in 0..<channelCount { sum += channels[channel][frame] }
                destination[frame] = sum * scale
            }
        }
        return count
    }

    private static func slotIndex(string: Int, fret: Int) -> Int? {
        guard (0..<stringCount).contains(string), (0...highestFret).contains(fret) else { return nil }
        return string * (highestFret + 1) + fret
    }

    // MARK: - Lookup

    var count: Int { byPosition.compactMap { $0 }.count }

    func sample(string: Int, fret: Int) -> Sample? {
        guard let slot = Self.slotIndex(string: string, fret: fret) else { return nil }
        return byPosition[slot]
    }

    /// Every position that was actually loaded, in neck order.
    var samples: [Sample] { byPosition.compactMap { $0 } }

    /// A pointer to one take's first frame. Valid for as long as this library
    /// is alive; the player holds a strong reference for exactly that reason.
    func audio(for sample: Sample) -> UnsafePointer<Float> {
        UnsafePointer(storage + sample.offset)
    }
}
