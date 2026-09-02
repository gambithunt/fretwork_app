import XCTest
@testable import Fretwork

/// Workstream 005 Phase 3: settings that outlive navigation, and detection that
/// idles when nothing is looking at it.
@MainActor
final class GlobalSettingsTests: XCTestCase {
    // MARK: - Board orientation

    /// It was a per-session flag that reset on every launch, so a player who
    /// prefers the player's-eye view re-flipped it each time. With a board on
    /// ten module screens it has to be one preference applied everywhere.
    func testTheBoardOrientationIsPersisted() {
        var settings = PracticeState.Settings()
        XCTAssertFalse(settings.isFretboardFlipped, "default is Low E on the bottom, matching the web app")

        settings.isFretboardFlipped = true
        var document = PracticeState()
        document.settings = settings

        let data = try? JSONEncoder().encode(document)
        let decoded = data.flatMap { try? JSONDecoder().decode(PracticeState.self, from: $0) }
        XCTAssertEqual(decoded?.settings.isFretboardFlipped, true)
    }

    /// Every other field decodes with a default, and this one must too — a
    /// document written before the field existed has to keep its devices.
    func testADocumentWithoutTheFieldStillDecodesEverythingElse() throws {
        let json = """
        {"version":1,"settings":{"tuningID":"dropD","sensitivity":0.7,"inputDeviceUID":"abc"},"modules":{}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.settings.isFretboardFlipped, "missing means default, not a decode failure")
        XCTAssertEqual(decoded.settings.tuningID, .dropD)
        XCTAssertEqual(decoded.settings.sensitivity, 0.7)
        XCTAssertEqual(decoded.settings.inputDeviceUID, "abc")
        XCTAssertFalse(decoded.settings.showsLiveNoteOnModules)
    }

    func testLiveNoteVisibilityRoundTripsAndDefaultsForOlderDocuments() throws {
        var settings = PracticeState.Settings()
        XCTAssertFalse(settings.showsLiveNoteOnModules)
        XCTAssertFalse(settings.highlightsLiveNoteOnFretboards)
        settings.showsLiveNoteOnModules = true
        settings.highlightsLiveNoteOnFretboards = true

        var document = PracticeState()
        document.settings = settings
        let restored = try JSONDecoder().decode(PracticeState.self, from: JSONEncoder().encode(document))
        XCTAssertTrue(restored.settings.showsLiveNoteOnModules)
        XCTAssertTrue(restored.settings.highlightsLiveNoteOnFretboards)
    }

    func testAnonymousUsageSharingIsOffByDefaultAndRoundTrips() throws {
        var settings = PracticeState.Settings()
        XCTAssertFalse(settings.sharesAnonymousUsageData)

        settings.sharesAnonymousUsageData = true
        var document = PracticeState()
        document.settings = settings
        let restored = try JSONDecoder().decode(PracticeState.self, from: JSONEncoder().encode(document))

        XCTAssertTrue(restored.settings.sharesAnonymousUsageData)
    }

    func testLiveNoteGlowPreferenceIsRestoredOntoAppState() {
        let state = AppState()
        XCTAssertEqual(state.highlightsLiveNoteOnFretboards, state.persistedLiveNoteHighlightForTesting)
    }

    /// A malformed value must not take the rest of the document with it — the
    /// field-by-field decode exists for exactly this.
    func testAMalformedOrientationDoesNotDestroyTheRestOfTheDocument() throws {
        let json = """
        {"version":1,"settings":{"tuningID":"openG","sensitivity":0.3,"isFretboardFlipped":"yes please"},"modules":{}}
        """
        let decoded = try JSONDecoder().decode(PracticeState.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.settings.isFretboardFlipped)
        XCTAssertEqual(decoded.settings.tuningID, .openG)
        XCTAssertEqual(decoded.settings.sensitivity, 0.3)
    }

    /// `CLAUDE.md` records this trap against `sensitivity`: a property observer
    /// does not fire for a value assigned inside the type's own initialiser, so
    /// a restored setting silently never reaches its side effect. The
    /// orientation must actually come back on the state object, not just in the
    /// document.
    func testTheOrientationIsRestoredOntoAppState() {
        let state = AppState()
        // Whatever this machine's saved document says, the two must agree —
        // that is the property, not a particular value.
        XCTAssertEqual(state.isFretboardFlipped, state.persistedFretboardFlipForTesting)
    }

    // MARK: - Detection gating

    /// Only the listening screen shows a live readout. A module screen should
    /// leave the detectors idle rather than paying for detection nobody sees.
    func testChordDetectionIdlesOnScreensThatShowNoReadout() {
        let state = AppState()
        state.detectionMode = .chords
        state.selectedScreen = .listen
        XCTAssertTrue(state.isChordDetectionActiveForTesting, "the listening screen in chord mode must detect")

        state.selectedScreen = .module(.pentatonic)
        XCTAssertFalse(state.isChordDetectionActiveForTesting, "a module screen must not hold the chord detector open")

        state.selectedScreen = .listen
        XCTAssertTrue(state.isChordDetectionActiveForTesting, "returning to Listen must bring detection back")
    }

    /// Note mode does not use the chord detector at all, on any screen.
    func testNoteModeNeverEnablesTheChordDetector() {
        let state = AppState()
        state.detectionMode = .notes
        for screen in AppScreen.all {
            state.selectedScreen = screen
            XCTAssertFalse(state.isChordDetectionActiveForTesting, "note mode enabled the chord detector on \(screen.id)")
        }
    }

    /// Gating flips a flag the workers already read. It must never renegotiate
    /// the device, which is what feeds the debounced restart path that exists
    /// because an uncapped restart loop was a real bug.
    func testGatingNeverRebuildsTheGraph() {
        let state = AppState()
        let before = state.graphBuildCount
        for _ in 0..<20 {
            state.detectionMode = .chords
            state.selectedScreen = .module(.notes)
            state.selectedScreen = .listen
            state.detectionMode = .notes
        }
        XCTAssertEqual(state.graphBuildCount, before)
    }
}
