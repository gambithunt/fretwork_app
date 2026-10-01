import SwiftUI
import UIKit

/// Non-DEBUG-safe facade over the `#if DEBUG` snapshot harness, so production
/// views never need their own `#if DEBUG` for capture hooks. In Release these
/// are inert constants.
enum IOSSnapshot {
    static var isActive: Bool {
        #if DEBUG
        IOSSnapshotHarness.isActive
        #else
        false
        #endif
    }

    static var showsUnlockSheet: Bool {
        #if DEBUG
        IOSSnapshotHarness.showsUnlockSheet
        #else
        false
        #endif
    }

    static var preferredColorScheme: ColorScheme {
        #if DEBUG
        IOSSnapshotHarness.preferredColorScheme
        #else
        .dark
        #endif
    }
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

    @MainActor
    static func requestOrientationIfNeeded() {
        #if DEBUG
        IOSSnapshotHarness.requestOrientationIfNeeded()
        #endif
    }

    static var initialPath: [AppScreen] {
        #if DEBUG
        IOSSnapshotHarness.initialPath
        #else
        [.listen]
        #endif
    }

    /// The split view's initial selection (iPad). `nil` leaves the default
    /// Listen selection; only module scenarios need to force a different one.
    static var initialSelection: AppScreen? {
        #if DEBUG
        IOSSnapshotHarness.initialSelection
        #else
        nil
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

    static var collapsesSidebar: Bool {
        #if DEBUG
        IOSSnapshotHarness.collapsesSidebar
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
