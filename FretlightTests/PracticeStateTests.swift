import XCTest
@testable import Fretwork

/// Storage that never touches a real defaults domain, and that records writes
/// so a test can assert one did *not* happen.
private final class FakeStorage: PracticeStorage {
    var document: Data?
    var legacy: [String: Any] = [:]
    private(set) var writeCount = 0

    init(document: Data? = nil, legacy: [String: Any] = [:]) {
        self.document = document
        self.legacy = legacy
    }

    func documentData() -> Data? { document }

    func writeDocument(_ data: Data) {
        document = data
        writeCount += 1
    }

    func legacyValue(forKey key: String) -> Any? { legacy[key] }
}

private func storage(json: String) -> FakeStorage {
    FakeStorage(document: Data(json.utf8))
}

@MainActor
final class PracticeStateTests: XCTestCase {
    func testNoDocumentAndNoLegacyKeysYieldsDefaults() {
        let store = PracticeStateStore(storage: FakeStorage())
        XCTAssertEqual(store.state, PracticeState())
        XCTAssertEqual(store.state.settings.tuningID, .standard)
        XCTAssertEqual(store.state.settings.sensitivity, SensitivitySettings.defaultValue)
        XCTAssertNil(store.state.settings.inputDeviceUID)
    }

    func testLoadingNeverWrites() {
        for fake in [FakeStorage(), storage(json: "not json at all"), storage(json: #"{"version":99}"#)] {
            _ = PracticeStateStore(storage: fake)
            XCTAssertEqual(fake.writeCount, 0)
        }
    }

    func testRoundTripPreservesEverySetting() {
        let fake = FakeStorage()
        let first = PracticeStateStore(storage: fake)
        first.update {
            $0.settings.tuningID = .dadgad
            $0.settings.sensitivity = 0.75
            $0.settings.inputDeviceUID = "input-uid"
            $0.settings.outputDeviceUID = "output-uid"
        }
        let reloaded = PracticeStateStore(storage: fake)
        XCTAssertEqual(reloaded.state, first.state)
        XCTAssertEqual(reloaded.state.settings.tuningID, .dadgad)
        XCTAssertEqual(reloaded.state.settings.sensitivity, 0.75)
        XCTAssertEqual(reloaded.state.settings.inputDeviceUID, "input-uid")
    }

    func testAChangeThatChangesNothingDoesNotWrite() {
        let fake = FakeStorage()
        let store = PracticeStateStore(storage: fake)
        store.update { $0.settings.sensitivity = 0.9 }
        XCTAssertEqual(fake.writeCount, 1)
        store.update { $0.settings.sensitivity = 0.9 }
        XCTAssertEqual(fake.writeCount, 1)
    }

    // MARK: - Documents that must not break launch

    func testCorruptDocumentFallsBackToDefaults() {
        for json in ["", "not json at all", "[]", #"{"settings":"a string"}"#, #"{"version":1,"settings":{"#] {
            let store = PracticeStateStore(storage: storage(json: json))
            XCTAssertEqual(store.state.settings, PracticeState.Settings(), json)
        }
    }

    func testFutureVersionFallsBackToDefaultsAndLeavesTheDocumentIntact() {
        let fake = storage(json: #"{"version":99,"settings":{"tuningID":"dadgad","sensitivity":0.9}}"#)
        let original = fake.document
        let store = PracticeStateStore(storage: fake)
        XCTAssertEqual(store.state.settings.tuningID, .standard)
        XCTAssertEqual(fake.document, original)
    }

    func testUnknownTuningFallsBackWithoutLosingTheOtherSettings() {
        let store = PracticeStateStore(storage: storage(
            json: #"{"version":1,"settings":{"tuningID":"retired-tuning","sensitivity":0.3,"inputDeviceUID":"kept"}}"#
        ))
        XCTAssertEqual(store.state.settings.tuningID, .standard)
        XCTAssertEqual(store.state.settings.sensitivity, 0.3)
        XCTAssertEqual(store.state.settings.inputDeviceUID, "kept")
    }

    func testOutOfRangeAndNonFiniteSensitivityIsClamped() {
        let high = PracticeStateStore(storage: storage(json: #"{"version":1,"settings":{"sensitivity":40}}"#))
        XCTAssertEqual(high.state.settings.sensitivity, 1)
        let low = PracticeStateStore(storage: storage(json: #"{"version":1,"settings":{"sensitivity":-4}}"#))
        XCTAssertEqual(low.state.settings.sensitivity, 0)
        // A non-finite value cannot round-trip through JSON, so it arrives as
        // a decode failure for that field rather than as a number to clamp.
        let bogus = PracticeStateStore(storage: storage(json: #"{"version":1,"settings":{"sensitivity":"NaN"}}"#))
        XCTAssertEqual(bogus.state.settings.sensitivity, SensitivitySettings.defaultValue)
    }

    func testMissingFieldsAndUnknownFieldsAreBothTolerated() {
        let store = PracticeStateStore(storage: storage(
            json: #"{"version":1,"settings":{"sensitivity":0.2,"somethingFromALaterBuild":{"a":1}},"modules":{},"extra":7}"#
        ))
        XCTAssertEqual(store.state.settings.sensitivity, 0.2)
        XCTAssertEqual(store.state.settings.tuningID, .standard)
        XCTAssertNil(store.state.settings.outputDeviceUID)
    }

    // MARK: - Migration off the loose keys

    func testLegacyKeysMigrateIntoTheDocument() {
        let store = PracticeStateStore(storage: FakeStorage(legacy: [
            "selectedInputDeviceUID": "legacy-input",
            "selectedOutputDeviceUID": "legacy-output",
            "sensitivity": 0.9
        ]))
        XCTAssertEqual(store.state.settings.inputDeviceUID, "legacy-input")
        XCTAssertEqual(store.state.settings.outputDeviceUID, "legacy-output")
        XCTAssertEqual(store.state.settings.sensitivity, 0.9)
    }

    func testAnExistingDocumentTakesPrecedenceOverLegacyKeys() {
        let fake = storage(json: #"{"version":1,"settings":{"inputDeviceUID":"current"}}"#)
        fake.legacy = ["selectedInputDeviceUID": "stale"]
        XCTAssertEqual(PracticeStateStore(storage: fake).state.settings.inputDeviceUID, "current")
    }

    func testLegacyMigrationLeavesTheOldKeysInPlaceForRollback() {
        let fake = FakeStorage(legacy: ["sensitivity": 0.9])
        _ = PracticeStateStore(storage: fake)
        XCTAssertEqual(fake.legacy["sensitivity"] as? Double, 0.9)
        XCTAssertEqual(fake.writeCount, 0)
    }

    func testLegacyNumericDeviceIDIsReadableForResolutionAgainstLiveDevices() {
        let store = PracticeStateStore(storage: FakeStorage(legacy: ["selectedInputDeviceID": UInt32(42)]))
        XCTAssertEqual(store.legacyDeviceID(forKey: "selectedInputDeviceID"), 42)
        XCTAssertNil(store.legacyDeviceID(forKey: "selectedOutputDeviceID"))
    }
}
