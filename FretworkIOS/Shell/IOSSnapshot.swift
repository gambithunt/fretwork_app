import UIKit

/// Non-DEBUG-safe facade over the `#if DEBUG` snapshot harness, so production
/// views never need their own `#if DEBUG` for capture hooks. In Release these
/// are inert constants.
enum IOSSnapshot {
    static var shouldSkipAudioSession: Bool {
        #if DEBUG
        IOSSnapshotHarness.shouldSkipAudioSession
        #else
        false
        #endif
    }

    static func effectiveStatus(_ actual: IOSAudioStatus?) -> IOSAudioStatus? {
        #if DEBUG
        IOSSnapshotHarness.effectiveStatus(actual)
        #else
        actual
        #endif
    }

    static func requestLandscapeIfNeeded() {
        #if DEBUG
        IOSSnapshotHarness.requestLandscapeIfNeeded()
        #endif
    }

    static var initialPath: [AppScreen] {
        #if DEBUG
        IOSSnapshotHarness.initialPath
        #else
        [.listen]
        #endif
    }

    static var showsSettingsSheet: Bool {
        #if DEBUG
        IOSSnapshotHarness.showsSettingsSheet
        #else
        false
        #endif
    }

    static var showsChordsDrawer: Bool {
        #if DEBUG
        IOSSnapshotHarness.showsChordsDrawer
        #else
        false
        #endif
    }
}
