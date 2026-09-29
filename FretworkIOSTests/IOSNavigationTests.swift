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
}
