import Foundation
import Observation
import StoreKit

/// The single source of truth for what the one-time unlock gates.
///
/// The free tier is Listen plus a fixed set of modules. It is keyed by module
/// id — never by index — so reordering `LearningModule` cannot silently move
/// the paywall, and it lives here rather than in a view so the list, the
/// unlock sheet and the tests all read the same set.
enum UnlockCatalog {
    /// The one non-consumable product. The price lives in App Store Connect;
    /// the bundled `Fretwork.storekit` carries only a local-testing price.
    static let productID = "org.fretwork.app.ios.unlock"

    /// The free modules, by module id. Listen is free too, but it isn't a
    /// `LearningModule`, so it has no entry here.
    static let freeModuleIDs: Set<String> = [LearningModule.notes.id]

    static func isFree(_ module: LearningModule) -> Bool {
        freeModuleIDs.contains(module.id)
    }

    /// The modules the paywall gates, in catalogue order.
    static var lockedModules: [LearningModule] {
        LearningModule.allCases.filter { !isFree($0) }
    }

    /// D-21: a restored path that ends on a locked module the user does not
    /// own falls back to the list rather than reopening gated content.
    static func sanitizedPath(_ path: [AppScreen], isUnlocked: Bool) -> [AppScreen] {
        guard let last = path.last, case .module(let module) = last,
              !isFree(module), !isUnlocked else { return path }
        return []
    }
}

/// The display data the paywall needs from the product. Kept as a plain value
/// so the store (and its tests) never have to construct a StoreKit `Product`.
struct IOSUnlockProductDisplay: Equatable {
    var displayName: String
    var displayPrice: String
}

enum IOSUnlockPurchaseResult: Equatable {
    case success
    case userCancelled
    case pending
}

/// The StoreKit operations `IOSUnlockStore` depends on, injected so the
/// entitlement logic is testable without a live store. The production
/// implementation is `IOSStoreKitGateway`.
@MainActor
protocol IOSUnlockStoreGateway {
    func loadDisplay() async -> IOSUnlockProductDisplay?
    /// Verified transaction product IDs currently entitled to the app.
    func verifiedEntitledProductIDs() async -> [String]
    /// Purchases the unlock product and finishes the verified transaction.
    func purchase() async throws -> IOSUnlockPurchaseResult
    /// `AppStore.sync()` followed by whatever the gateway must finish.
    func restore() async throws
}

/// The StoreKit 2 entitlement model behind the one-time iOS unlock.
///
/// Owns the product load, the launch-time entitlement check, the lifetime
/// `Transaction.updates` listener, purchases (success / cancelled / pending)
/// and `AppStore.sync()` restore. Unverified transactions grant nothing.
@MainActor
@Observable
final class IOSUnlockStore {
    private(set) var isUnlocked = false
    private(set) var displayName: String?
    private(set) var displayPrice: String?
    private(set) var isPurchasing = false
    /// The last terminal outcome, surfaced by the sheet and Settings.
    private(set) var statusMessage: String?

    private var updatesTask: Task<Void, Never>?
    private let gateway: any IOSUnlockStoreGateway

    init(gateway: any IOSUnlockStoreGateway = IOSStoreKitGateway()) {
        self.gateway = gateway
    }

    /// Starts the lifetime transaction listener. Call once at app launch.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                await self.apply(result)
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    /// Reads verified current entitlements and marks the unlock owned when the
    /// product is present.
    func refreshEntitlements() async {
        let productIDs = await gateway.verifiedEntitledProductIDs()
        if productIDs.contains(UnlockCatalog.productID) {
            isUnlocked = true
        }
    }

    func loadProduct() async {
        #if DEBUG
        if IOSSnapshot.isActive {
            let snapshot = Self.snapshotProductDisplay()
            displayName = snapshot.name
            displayPrice = snapshot.price
            return
        }
        #endif
        if let display = await gateway.loadDisplay() {
            displayName = display.displayName
            displayPrice = display.displayPrice
        }
    }

    func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            switch try await gateway.purchase() {
            case .success:
                isUnlocked = true
            case .userCancelled:
                statusMessage = nil
            case .pending:
                statusMessage = "Waiting for approval. You'll be unlocked as soon as it's approved."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func restore() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            try await gateway.restore()
            await refreshEntitlements()
            if !isUnlocked {
                statusMessage = "No previous purchase was found."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Applies a live update — a purchase completed on this or another device.
    func apply(_ result: VerificationResult<Transaction>) async {
        guard let transaction = IOSStoreKitGateway.verified(result) else { return }
        if transaction.productID == UnlockCatalog.productID {
            isUnlocked = true
        }
        await transaction.finish()
    }

    #if DEBUG
    /// Snapshot fixture: the app-under-capture runs without the scheme's
    /// StoreKit configuration, so the product cannot load. Read the test price
    /// from the bundled `.storekit` file instead of hard-coding one.
    private static func snapshotProductDisplay() -> (name: String, price: String) {
        guard let url = Bundle.main.url(forResource: "Fretwork", withExtension: "storekit"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]],
              let product = products.first(where: { $0["productID"] as? String == UnlockCatalog.productID }) else {
            return ("Fretwork Unlock", "…")
        }
        let name = (product["localizations"] as? [[String: Any]])?.first?["displayName"] as? String
            ?? "Fretwork Unlock"
        guard let amount = product["displayPrice"] as? String else {
            return (name, "…")
        }
        let localeID = (json["settings"] as? [String: Any])?["_locale"] as? String ?? "en_US"
        let symbol = Locale(identifier: localeID).currencySymbol ?? ""
        return (name, symbol + amount)
    }
    #endif
}

/// The production StoreKit 2 gateway. Thin: it translates the store's needs
/// into StoreKit 2 calls and finishes every verified transaction.
struct IOSStoreKitGateway: IOSUnlockStoreGateway {
    func loadDisplay() async -> IOSUnlockProductDisplay? {
        let products = (try? await Product.products(for: [UnlockCatalog.productID])) ?? []
        guard let product = products.first else { return nil }
        return IOSUnlockProductDisplay(displayName: product.displayName, displayPrice: product.displayPrice)
    }

    func verifiedEntitledProductIDs() async -> [String] {
        var ids: [String] = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.verified(result) else { continue }
            ids.append(transaction.productID)
            await transaction.finish()
        }
        return ids
    }

    func purchase() async throws -> IOSUnlockPurchaseResult {
        let products = try await Product.products(for: [UnlockCatalog.productID])
        guard let product = products.first else {
            throw UnlockStoreGatewayError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(let result):
            guard let transaction = Self.verified(result) else {
                throw UnlockStoreGatewayError.unverifiedTransaction
            }
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            throw UnlockStoreGatewayError.unknownResult
        }
    }

    func restore() async throws {
        try await AppStore.sync()
    }

    /// Unverified transactions grant nothing.
    static func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let value): value
        case .unverified: nil
        }
    }
}

enum UnlockStoreGatewayError: LocalizedError {
    case productUnavailable
    case unverifiedTransaction
    case unknownResult

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "The unlock product isn't available right now."
        case .unverifiedTransaction: "This purchase couldn't be verified."
        case .unknownResult: "Something went wrong. Please try again."
        }
    }
}
