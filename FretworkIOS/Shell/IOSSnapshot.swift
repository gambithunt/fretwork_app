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

    static var showsModuleDrawer: Bool {
        #if DEBUG
        IOSSnapshotHarness.showsModuleDrawer
        #else
        false
        #endif
    }

    static var guidedRunActive: Bool {
        #if DEBUG
        IOSSnapshotHarness.guidedRunActive
        #else
        false
        #endif
    }

    /// The Triads snapshot opens on its Paths face, which is otherwise only
    /// reachable by a tap in the drawer.
    static var forcesTriadsPathMode: Bool {
        #if DEBUG
        IOSSnapshotHarness.forcesTriadsPathMode
        #else
        false
        #endif
    }

    static var schedulesPopBack: Bool {
        #if DEBUG
        IOSSnapshotHarness.schedulesPopBack
        #else
        false
        #endif
    }

    static let popBackNotificationName = Notification.Name("FretworkIOSSnapshotPopBack")
}
