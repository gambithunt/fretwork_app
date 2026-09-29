import SwiftUI
import XCTest
@testable import Fretwork

/// The status → surface and status → pill appearance mappings are pure, so the
/// Phase 4 surfaces (D-10) are covered without any audio controller.
@MainActor
final class IOSStatusSurfaceTests: XCTestCase {
    func testPermissionDeniedMapsToDeniedSurface() {
        XCTAssertEqual(IOSStatusSurfaceMapper.surface(for: .permissionDenied), .permissionDenied)
    }

    func testInterruptedMapsToInterruptedSurface() {
        XCTAssertEqual(IOSStatusSurfaceMapper.surface(for: .interrupted), .interrupted)
    }

    func testFailedCarriesItsMessage() {
        XCTAssertEqual(IOSStatusSurfaceMapper.surface(for: .failed("boom")), .failed("boom"))
    }

    func testHealthyStatusesProduceNoSurface() {
        XCTAssertEqual(IOSStatusSurfaceMapper.surface(for: .listening), .none)
        XCTAssertEqual(IOSStatusSurfaceMapper.surface(for: .starting), .none)
        XCTAssertEqual(IOSStatusSurfaceMapper.surface(for: .idle), .none)
        XCTAssertEqual(IOSStatusSurfaceMapper.surface(for: nil), .none)
    }

    func testAppearanceTitles() {
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .listening).title, "Listening")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .starting).title, "Starting…")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .interrupted).title, "Paused")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .permissionDenied).title, "Mic off")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .failed("x")).title, "Audio error")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .idle).title, "Stopped")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: nil).title, "Stopped")
    }

    func testAppearanceTintsUseColourAsAReinforcementOnly() {
        // Colour is never the only cue: every appearance carries a text title,
        // and the tints below only reinforce it (D-09).
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .listening).tint, .green)
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .interrupted).tint, .orange)
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .permissionDenied).tint, .red)
    }
}
