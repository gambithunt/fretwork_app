import Foundation
@testable import Fretwork

/// A deterministic `AudioControlling` for the shared-surface tests.
///
/// Records what `AppState` asks of it and lets a test emit events back, so the
/// seam can be exercised with no device and no HAL — constructing a real
/// `MacAudioController` enumerates devices in its initialiser, which is the
/// documented ~30s cost in the test host when the microphone grant is missing.
@MainActor
final class FakeAudioController: AudioControlling {
    var onEvent: (@MainActor @Sendable (AudioControllerEvent) -> Void)?

    // MARK: - start()/stop()

    /// Whether a `start()` reports that it actually issued a start. The Retry
    /// gating test flips this; the default mirrors a normal controller.
    var starts = true
    private(set) var startCount = 0
    private(set) var stoppedCount = 0

    // MARK: - Detection gating / sensitivity

    /// Every value ever handed to `setChordDetectionEnabled`, in order, so a
    /// test can assert both the latest value and that no spurious calls happen.
    private(set) var chordDetectionValues: [Bool] = []
    var chordDetectionEnabled: Bool { chordDetectionValues.last ?? false }

    private(set) var sensitivityValues: [Double] = []
    var sensitivity: Double { sensitivityValues.last ?? 0.5 }

    // MARK: - Sample playback

    private(set) var prepareSamplePlaybackCount = 0
    var prepareError: String?
    var isSamplePlaybackReady = false
    var isSampleLibraryLoaded = false
    private(set) var played: [(string: Int, fret: Int, tuning: Tuning)] = []

    // MARK: - AudioControlling

    @discardableResult
    func start() -> Bool {
        startCount += 1
        return starts
    }

    func stop() { stoppedCount += 1 }

    func setChordDetectionEnabled(_ enabled: Bool) { chordDetectionValues.append(enabled) }

    func setSensitivity(_ value: Double) { sensitivityValues.append(value) }

    func prepareSamplePlayback(completion: (@Sendable (String?) -> Void)?) {
        prepareSamplePlaybackCount += 1
        isSampleLibraryLoaded = true
        completion?(prepareError)
    }

    func playSample(string: Int, fret: Int, tuning: Tuning) {
        played.append((string, fret, tuning))
    }

    /// Delivers an event the way the platform controller would: on the main
    /// actor, through the one `onEvent` the owner subscribed.
    func emit(_ event: AudioControllerEvent) { onEvent?(event) }
}

/// In-memory `PracticeStorage` so tests never touch the real defaults domain.
final class InMemoryPracticeStorage: PracticeStorage {
    private var data: Data?

    func documentData() -> Data? { data }
    func writeDocument(_ data: Data) { self.data = data }
    func legacyValue(forKey key: String) -> Any? { nil }
}
