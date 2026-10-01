import StoreKitTest
import XCTest
@testable import Fretwork

/// Entitlement logic and the one-time unlock.
///
/// The purchase/restore/pending matrix runs against a fake gateway so it is
/// deterministic; the StoreKit *configuration file* itself is validated with
/// `SKTestSession` (a fresh session is locked, and the bundled
/// `Fretwork.storekit` loads and declares the product). A full `SKTestSession`
/// purchase flow can't run in the headless `xcodebuild` test host: the host is
/// not launched with StoreKit Testing in Xcode, so `storekitd` answers
/// `notEntitled` to every purchase. That is an environment constraint, not a
/// store defect — the same store unlocks under the fake and in the app.
@MainActor
final class IOSUnlockStoreTests: XCTestCase {
    // MARK: - StoreKit configuration (SKTestSession)

    func testFreshSessionIsLocked() async throws {
        let session = try Self.makeSession()
        defer { session.clearTransactions() }
        let store = IOSUnlockStore(gateway: IOSStoreKitGateway())
        await store.refreshEntitlements()
        XCTAssertFalse(store.isUnlocked)
    }

    func testBundledStoreKitConfigurationDeclaresTheUnlockProduct() throws {
        let session = try Self.makeSession()
        defer { session.clearTransactions() }
        XCTAssertTrue(session.allTransactions().isEmpty)

        let data = try Data(contentsOf: try Self.storeKitURL())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product["productID"] as? String, UnlockCatalog.productID)
        XCTAssertEqual(product["type"] as? String, "NonConsumable")
    }

    // MARK: - Purchase / restore / pending (fake gateway)

    func testPurchaseUnlocks() async {
        let gateway = FakeUnlockGateway()
        let store = IOSUnlockStore(gateway: gateway)
        await store.loadProduct()
        XCTAssertEqual(store.displayPrice, "$19.99")

        await store.purchase()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertNil(store.statusMessage)
    }

    func testPendingPurchaseStaysLocked() async {
        let gateway = FakeUnlockGateway(purchaseResult: .success(.pending))
        let store = IOSUnlockStore(gateway: gateway)
        await store.purchase()
        XCTAssertFalse(store.isUnlocked)
        XCTAssertNotNil(store.statusMessage)
    }

    func testUserCancelledPurchaseStaysLocked() async {
        let gateway = FakeUnlockGateway(purchaseResult: .success(.userCancelled))
        let store = IOSUnlockStore(gateway: gateway)
        await store.purchase()
        XCTAssertFalse(store.isUnlocked)
        XCTAssertNil(store.statusMessage)
    }

    func testRestoreUnlocks() async {
        let gateway = FakeUnlockGateway()
        let store = IOSUnlockStore(gateway: gateway)
        await store.restore()
        XCTAssertTrue(gateway.didRestore)
        XCTAssertTrue(store.isUnlocked)
    }

    // MARK: - Free tier

    func testFreeSetIsExactlyListenAndNotes() {
        XCTAssertEqual(UnlockCatalog.freeModuleIDs, ["notes"])
        XCTAssertEqual(UnlockCatalog.lockedModules.map(\.id), [
            "intervals", "octaves", "triads", "chords", "pentatonic",
            "scales", "harmonizing", "noteAssociation", "circle"
        ])
    }

    // MARK: - D-21 restore guard

    func testSanitizedPathDropsLockedModuleWhenNotEntitled() {
        XCTAssertEqual(
            UnlockCatalog.sanitizedPath([.module(.chords)], isUnlocked: false),
            [AppScreen]()
        )
    }

    func testSanitizedPathKeepsFreeAndUnlockedModules() {
        XCTAssertEqual(
            UnlockCatalog.sanitizedPath([.module(.notes)], isUnlocked: false),
            [AppScreen.module(.notes)]
        )
        XCTAssertEqual(
            UnlockCatalog.sanitizedPath([.module(.chords)], isUnlocked: true),
            [AppScreen.module(.chords)]
        )
        XCTAssertEqual(
            UnlockCatalog.sanitizedPath([.listen], isUnlocked: false),
            [AppScreen.listen]
        )
    }

    // MARK: - Helpers

    private static func storeKitURL() throws -> URL {
        try XCTUnwrap(
            Bundle.main.url(forResource: "Fretwork", withExtension: "storekit"),
            "Fretwork.storekit must be bundled with the app target"
        )
    }

    private static func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(contentsOf: storeKitURL())
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }
}

/// Deterministic `IOSUnlockStoreGateway`.
@MainActor
private final class FakeUnlockGateway: IOSUnlockStoreGateway {
    var display: IOSUnlockProductDisplay? = IOSUnlockProductDisplay(
        displayName: "Fretwork Unlock",
        displayPrice: "$19.99"
    )
    var entitledIDs: [String] = []
    var purchaseResult: Result<IOSUnlockPurchaseResult, Error> = .success(.success)
    var restoreError: Error?
    private(set) var didRestore = false

    init(purchaseResult: Result<IOSUnlockPurchaseResult, Error> = .success(.success)) {
        self.purchaseResult = purchaseResult
    }

    func loadDisplay() async -> IOSUnlockProductDisplay? { display }

    func verifiedEntitledProductIDs() async -> [String] { entitledIDs }

    func purchase() async throws -> IOSUnlockPurchaseResult {
        try purchaseResult.get()
    }

    func restore() async throws {
        didRestore = true
        if let restoreError { throw restoreError }
        entitledIDs = [UnlockCatalog.productID]
    }
}
