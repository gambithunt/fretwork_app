import Foundation

/// What a platform audio controller reports back to `AppState`.
/// All payloads are value types already in the shared layer.
enum AudioControllerEvent: Sendable {
    case noteUpdate(PitchDisplayState)
    case chordUpdate(ChordDisplayState)
    case error(String)
    case recovered
    case reconnecting
}

/// The platform-neutral audio-controller surface `AppState` depends on.
///
/// Production implementations: `MacAudioController` (macOS, HAL + AVAudioEngine)
/// and an `AVAudioSession`-backed iOS controller (Phase 3). Tests and SwiftUI
/// previews use a deterministic fake. Device enumeration/selection, monitor
/// routing, direct-path suggestions and `AudioDeviceID` are deliberately absent:
/// they are Mac-only concerns owned by the Mac controller (see
/// `MacAudioController`).
@MainActor
protocol AudioControlling: AnyObject {
    /// Outbound events. Set once by the owner before `start()`. The platform
    /// controller delivers these on the main actor.
    var onEvent: (@Sendable (AudioControllerEvent) -> Void)? { get set }

    /// Lifecycle. Parameterless by design: device selection is the Mac
    /// controller's own state; the iOS controller manages its AVAudioSession.
    func start()
    func stop()

    /// Notes/Chords gating. Must only flip the worker flag — never rebuild the
    /// graph (a rebuild feeds the debounced restart path; `AppShellNavigationTests`
    /// asserts the build count never moves).
    func setChordDetectionEnabled(_ enabled: Bool)

    /// 0...1 sensitivity, mapped inside the controller to the detector's DSP
    /// knobs (Mac: `SensitivitySettings`).
    func setSensitivity(_ value: Double)

    /// Decodes the bundled note library and attaches a player. Completion
    /// receives a user-presentable error on failure, nil on success. Safe to
    /// call repeatedly; the library is decoded once.
    func prepareSamplePlayback(completion: (@Sendable (String?) -> Void)?)

    /// True when a note would actually sound right now (library decoded AND a
    /// running graph has a player attached). Exists because its absence was
    /// invisible: `playSample` is a silent no-op otherwise.
    var isSamplePlaybackReady: Bool { get }

    /// True once the bundled library is decoded, whether or not a graph is
    /// running — lets tests assert the library was *asked for* without hardware.
    var isSampleLibraryLoaded: Bool { get }

    /// Sounds one position in `tuning`. No-op until `prepareSamplePlayback` has
    /// completed and a graph is running.
    func playSample(string: Int, fret: Int, tuning: Tuning)
}
