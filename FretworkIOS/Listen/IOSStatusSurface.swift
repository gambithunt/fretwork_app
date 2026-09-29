import SwiftUI

/// The explicit Listen surfaces a given controller status needs (D-10).
///
/// Kept separate from the views so the mapping is unit-testable without
/// standing up an `AppState` or an audio controller.
enum IOSStatusSurface: Equatable {
    case none
    case permissionDenied
    case interrupted
    case failed(String)
}

enum IOSStatusSurfaceMapper {
    static func surface(for status: IOSAudioStatus?) -> IOSStatusSurface {
        switch status {
        case .permissionDenied: return .permissionDenied
        case .interrupted: return .interrupted
        case .failed(let message): return .failed(message)
        case .listening, .starting, .idle, nil: return .none
        }
    }
}

/// The status pill's text and tint, also as a pure mapping.
struct IOSStatusAppearance: Equatable {
    let title: String
    let tint: Color
}

enum IOSStatusAppearanceMapper {
    static func appearance(for status: IOSAudioStatus?) -> IOSStatusAppearance {
        switch status {
        case .listening: IOSStatusAppearance(title: "Listening", tint: .green)
        case .starting: IOSStatusAppearance(title: "Starting…", tint: .orange)
        case .interrupted: IOSStatusAppearance(title: "Paused", tint: .orange)
        case .permissionDenied: IOSStatusAppearance(title: "Mic off", tint: .red)
        case .failed: IOSStatusAppearance(title: "Audio error", tint: .red)
        case .idle, nil: IOSStatusAppearance(title: "Stopped", tint: .secondary)
        }
    }
}

/// Whether the Listen screen should issue a start right now.
///
/// Pure decision, testable without a controller or view. `.undetermined` still
/// starts (that is the first-run system prompt); `.denied` never starts from
/// here — the explicit Open Settings surface owns recovery until the user
/// grants. Status must be `.idle`/`nil` so a live run is never restarted.
enum IOSStartDecision {
    static func shouldStart(
        status: IOSAudioStatus?,
        permission: IOSAudioRecordPermission?,
        isListenVisible: Bool,
        sceneActive: Bool
    ) -> Bool {
        guard isListenVisible, sceneActive else { return false }
        guard status == .idle || status == nil else { return false }
        switch permission {
        case .granted, .undetermined: return true
        case .denied, nil: return false
        }
    }
}
