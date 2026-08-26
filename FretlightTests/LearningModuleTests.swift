import XCTest
@testable import Fretwork

/// `LearningModule` mirrors `../fretwork/src/lib/modules/catalog.json`. The two
/// apps teach the same course, so a module titled one thing on the web and
/// another here — or ordered third in one and fifth in the other — is a real
/// defect, just a quiet one.
///
/// These tests read the web's catalogue directly when the repo is beside this
/// one, which is the arrangement `docs/workstreams/README.md` describes as the
/// source of truth. When it is not present (CI, a fresh clone) the comparison
/// tests skip rather than fail: they are a drift alarm, not a build dependency.
final class LearningModuleTests: XCTestCase {
    private struct CatalogEntry: Decodable {
        let id: String
        let stateId: String
        let title: String
        let blurb: String
    }

    /// Reads the web's catalogue — **only** when `FRETWORK_WEB_REPO` points at
    /// the checkout, following the opt-in convention
    /// `DetectionBoardSnapshotTests` already uses.
    ///
    /// This used to resolve `../fretwork` from `#filePath` and read it
    /// unconditionally. The test host is a sandboxed app, and a read outside
    /// its container needs a Documents-folder grant that a headless
    /// `xcodebuild` run has nobody to approve — so the read blocked
    /// indefinitely and the suite stalled with no failure and no message. A
    /// unit test must not reach outside the test bundle for a file it needs.
    private func loadWebCatalog() throws -> [CatalogEntry] {
        guard let root = ProcessInfo.processInfo.environment["FRETWORK_WEB_REPO"] else {
            throw XCTSkip("set TEST_RUNNER_FRETWORK_WEB_REPO to the web checkout to compare against the live catalogue")
        }
        let catalog = URL(fileURLWithPath: root).appendingPathComponent("src/lib/modules/catalog.json")
        guard FileManager.default.fileExists(atPath: catalog.path) else {
            throw XCTSkip("no catalog.json under \(root)")
        }
        return try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: catalog))
    }

    func testTheModuleOrderMatchesTheWebApp() throws {
        let web = try loadWebCatalog()
        XCTAssertEqual(
            LearningModule.allCases.map(\.catalogID),
            web.map(\.id),
            "module order or membership has drifted from the web app's catalogue"
        )
    }

    func testEveryTitleAndBlurbMatchesTheWebApp() throws {
        let web = try loadWebCatalog()
        for (module, entry) in zip(LearningModule.allCases, web) {
            XCTAssertEqual(module.title, entry.title, "title drift on \(entry.id)")
            XCTAssertEqual(module.blurb, entry.blurb, "blurb drift on \(entry.id)")
        }
    }

    /// The web keeps a kebab-case route id and a camelCase state key, and both
    /// are load-bearing there. Only one module differs between them, and it is
    /// exactly the kind of detail a port gets wrong.
    func testTheStateKeysMatchTheWebApp() throws {
        let web = try loadWebCatalog()
        for (module, entry) in zip(LearningModule.allCases, web) {
            XCTAssertEqual(module.rawValue, entry.stateId, "state key drift on \(entry.id)")
        }
    }

    // MARK: - Local invariants, which hold with or without the web repo

    func testThereAreTenModules() {
        XCTAssertEqual(LearningModule.allCases.count, 10)
    }

    func testEveryModuleHasDistinctIdentityAndCopy() {
        XCTAssertEqual(Set(LearningModule.allCases.map(\.id)).count, 10)
        XCTAssertEqual(Set(LearningModule.allCases.map(\.catalogID)).count, 10)
        XCTAssertEqual(Set(LearningModule.allCases.map(\.title)).count, 10)
        XCTAssertEqual(Set(LearningModule.allCases.map(\.blurb)).count, 10)
        XCTAssertEqual(Set(LearningModule.allCases.map(\.symbol)).count, 10, "a repeated sidebar icon reads as a duplicate entry")
    }

    /// Fret ceilings differ per module, and carrying that difference is what
    /// stops a shape being drawn off the end of its own board.
    func testFretCeilingsMatchTheWebModules() {
        XCTAssertEqual(LearningModule.pentatonic.highestFret, 15)
        XCTAssertEqual(LearningModule.chords.highestFret, 15)
        XCTAssertEqual(LearningModule.triads.highestFret, 22)
        for module in LearningModule.allCases where ![.pentatonic, .chords, .triads].contains(module) {
            XCTAssertEqual(module.highestFret, 12, "\(module.id) should use the shared 12-fret board")
        }
        for module in LearningModule.allCases {
            XCTAssertLessThanOrEqual(module.highestFret, NoteSampleLibrary.highestFret,
                                     "\(module.id) draws past the highest recorded position")
        }
    }

    // MARK: - Screens

    func testListenComesFirstAndEveryModuleFollows() {
        XCTAssertEqual(AppScreen.all.first, .listen)
        XCTAssertEqual(AppScreen.all.count, 11)
        XCTAssertEqual(Set(AppScreen.all.map(\.id)).count, 11)
        XCTAssertEqual(Array(AppScreen.all.dropFirst()), LearningModule.allCases.map(AppScreen.module))
    }

    /// Detection is what costs CPU when nothing needs it. Only the listening
    /// screen consumes it today.
    func testOnlyTheListeningScreenNeedsDetection() {
        XCTAssertTrue(AppScreen.listen.needsDetection)
        for module in LearningModule.allCases {
            XCTAssertFalse(AppScreen.module(module).needsDetection, "\(module.id) should not hold the detectors open")
        }
    }
}
