import Foundation

/// The richer iOS state machine, owned by `IOSAudioController`.
///
/// Deliberately **not** part of the shared `AudioControllerEvent` enum: the four
/// existing cases already carry everything `AppState` (the shared consumer)
/// needs, and adding an iOS-only case would force the Mac side to compile an
/// enum it never produces. The iOS shell reads this surface through the
/// `AppState.iosAudio` cast (see `FretworkIOS/AppState+IOS.swift`), the same
/// way Mac views read `AppState.macAudio`.
enum IOSAudioStatus: Equatable, Sendable {
    case idle
    case starting
    case listening
    case interrupted
    case permissionDenied
    case failed(String)
}

/// The microphone grant as the controller sees it, decoupled from
/// `AVAudioApplication.RecordPermission` so the state machine can be unit-tested
/// with no real session.
enum IOSAudioRecordPermission: Equatable, Sendable {
    case undetermined
    case granted
    case denied
}
