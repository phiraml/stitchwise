import Foundation
import Observation
import StoreKit
import StitchCore

/// One non-consumable product, bought once, owned forever.
///
/// There is no subscription, no trial timer and no receipt-validation server. Entitlement
/// is read from StoreKit's local `currentEntitlements`, so the app works fully offline and
/// a lapsed network connection can never demote a paying user.
@Observable
@MainActor
final class PurchaseManager {
    static let productID = "com.stitchwise.lifetime"

    private(set) var entitlement: Entitlement = .free
    private(set) var product: Product?
    private(set) var purchaseInFlight = false
    private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    func start() async {
        await loadProduct()
        await refreshEntitlement()
        listenForTransactions()
    }

    /// Deliberately no `deinit` cancellation. Under Swift 6, `deinit` is nonisolated and
    /// cannot touch main-actor state, so `updatesTask?.cancel()` there does not compile.
    /// This object lives for the lifetime of the app and the task captures `self` weakly,
    /// so nothing leaks; `stop()` exists for tests and previews that need to tear it down.
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            lastError = "Could not load the store: \(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                entitlement = .lifetime
                return
            }
        }
        entitlement = .free
    }

    /// StoreKit delivers transactions completed outside the app (Ask to Buy, another
    /// device, a refund) on this stream. Without it a purchase can land and never unlock.
    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    func purchase() async {
        guard let product, !purchaseInFlight else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            lastError = "Could not restore: \(error.localizedDescription)"
        }
    }

    var displayPrice: String { product?.displayPrice ?? "—" }
}
