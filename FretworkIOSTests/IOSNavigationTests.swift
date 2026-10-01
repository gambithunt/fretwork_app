import UIKit
import XCTest
@testable import Fretwork

/// The idiom → navigation decision is a pure function (D-24): phone is always
/// a full-screen stack, everything else gets the split view.
@MainActor
final class IOSNavigationTests: XCTestCase {
    func testPhoneAlwaysUsesStack() {
        XCTAssertEqual(IOSNavigation.kind(for: .phone), .stack)
    }

    func testPadUsesSplit() {
        XCTAssertEqual(IOSNavigation.kind(for: .pad), .split)
    }

    func testNonPhoneNonPadIdiomsFallBackToSplit() {
        XCTAssertEqual(IOSNavigation.kind(for: .tv), .split)
        XCTAssertEqual(IOSNavigation.kind(for: .carPlay), .split)
        XCTAssertEqual(IOSNavigation.kind(for: .mac), .split)
    }

    // MARK: - Orientation (iPad reports regular size classes in both axes)

    func testPhoneIsLandscapeOnlyWhenHeightIsCompact() {
        // A Pro Max in landscape is regular-width but compact-height; in
        // portrait it is regular in both axes.
        XCTAssertTrue(IOSOrientation.isLandscape(
            idiom: .phone, verticalSizeClass: .compact, viewportWidth: 844, viewportHeight: 390
        ))
        XCTAssertFalse(IOSOrientation.isLandscape(
            idiom: .phone, verticalSizeClass: .regular, viewportWidth: 390, viewportHeight: 844
        ))
    }

    func testPadIsLandscapeByViewportNotSizeClass() {
        // The iPad reports .regular/.regular in both orientations, so only the
        // measured viewport can tell them apart.
        XCTAssertTrue(IOSOrientation.isLandscape(
            idiom: .pad, verticalSizeClass: .regular, viewportWidth: 1376, viewportHeight: 1032
        ))
        XCTAssertFalse(IOSOrientation.isLandscape(
            idiom: .pad, verticalSizeClass: .regular, viewportWidth: 1032, viewportHeight: 1376
        ))
    }

    func testPadLandscapeDoesNotCareAboutCompactSizeClass() {
        // Even if the iPad ever reported a compact height, the idiom rule wins
        // over the size-class rule.
        XCTAssertTrue(IOSOrientation.isLandscape(
            idiom: .pad, verticalSizeClass: .compact, viewportWidth: 1376, viewportHeight: 1032
        ))
    }
}
