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

    func testPlayingOverridesListeningOnly() {
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .listening, playing: true).title, "Playing")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .listening, playing: true).tint, .orange)
        // Playing must never mask a non-listening state (idle/failure/etc.).
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .idle, playing: true).title, "Stopped")
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .failed("x"), playing: true).title, "Audio error")
    }

    func testStartDecision() {
        // idle + granted/undetermined + active -> start (recovery / first-run).
        XCTAssertTrue(IOSStartDecision.shouldStart(
            status: .idle, permission: .granted, sceneActive: true))
        XCTAssertTrue(IOSStartDecision.shouldStart(
            status: .idle, permission: .undetermined, sceneActive: true))
        // denied -> the Open Settings surface owns recovery, never auto-start.
        XCTAssertFalse(IOSStartDecision.shouldStart(
            status: .idle, permission: .denied, sceneActive: true))
        // backgrounded -> no.
        XCTAssertFalse(IOSStartDecision.shouldStart(
            status: .idle, permission: .granted, sceneActive: false))
        // a live run must never be restarted.
        XCTAssertFalse(IOSStartDecision.shouldStart(
            status: .listening, permission: .granted, sceneActive: true))
        XCTAssertFalse(IOSStartDecision.shouldStart(
            status: .interrupted, permission: .granted, sceneActive: true))
    }

    func testAppearanceCarriesTextTitleForEveryState() {
        // Colour is never the only cue: every appearance carries a non-empty
        // text title alongside its tint (D-09).
        let statuses: [IOSAudioStatus?] = [
            .listening, .starting, .interrupted, .permissionDenied, .failed("x"), .idle, nil
        ]
        for status in statuses {
            XCTAssertFalse(
                IOSStatusAppearanceMapper.appearance(for: status).title.isEmpty,
                "appearance for \(String(describing: status)) must carry a text title"
            )
        }
    }

    func testAppearanceTintsUseColourAsAReinforcementOnly() {
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .listening).tint, .green)
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .interrupted).tint, .orange)
        XCTAssertEqual(IOSStatusAppearanceMapper.appearance(for: .permissionDenied).tint, .red)
    }
}
