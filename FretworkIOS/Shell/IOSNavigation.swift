import SwiftUI
import UIKit

/// How the iOS shell presents its top level.
///
/// Decided by device idiom, never by size class (D-24): a landscape Pro Max is
/// regular-width, so a size-class split view would sit the list beside the
/// neck and waste ~40% of the width.
enum IOSNavigationKind: Equatable, Sendable {
    case stack
    case split
}

enum IOSNavigation {
    /// Pure function: the navigation decision, testable without any UI.
    static func kind(for idiom: UIUserInterfaceIdiom) -> IOSNavigationKind {
        idiom == .phone ? .stack : .split
    }
}

/// Whether a screen lays out as landscape.
///
/// Decided by idiom because iPad reports regular size classes in *both* axes:
/// `verticalSizeClass == .compact` only ever means "landscape" on a phone. On
/// an iPad the physical viewport is the only signal, so the root shell measures
/// it and publishes the answer through `fretworkIsLandscape`.
enum IOSOrientation {
    static func isLandscape(
        idiom: UIUserInterfaceIdiom,
        verticalSizeClass: UserInterfaceSizeClass?,
        viewportWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> Bool {
        switch idiom {
        case .phone:
            return verticalSizeClass == .compact
        default:
            return viewportWidth > viewportHeight
        }
    }
}

extension EnvironmentValues {
    /// The idiom-aware landscape decision, published once by the root shell so
    /// every screen agrees without each re-deriving it from geometry.
    var fretworkIsLandscape: Bool {
        get { self[FretworkIsLandscapeKey.self] }
        set { self[FretworkIsLandscapeKey.self] = newValue }
    }
}

private struct FretworkIsLandscapeKey: EnvironmentKey {
    static let defaultValue = false
}
