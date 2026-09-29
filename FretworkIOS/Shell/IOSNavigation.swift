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
