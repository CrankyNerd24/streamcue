import StoreKit
import Observation

/// One-time, non-consumable unlock for household sharing and automatic
/// Reminders sync. StoreKit's own transaction history is the source of
/// truth — nothing is cached beyond what `Transaction.currentEntitlements`
/// already persists on-device.
@MainActor
@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    /// Placeholder — no App Store Connect product exists yet. Replace with
    /// the real product ID before this ships.
    static let premiumProductID = "com.CrankyNerdNew.StreamCue.premium"

    private(set) var isPremium = false
    private(set) var product: Product?
    private(set) var isWorking = false
    var errorMessage: String?

    // `shared` lives for the app's whole lifetime, so this task is never
    // cancelled — there's no deinit to do it from.
    private init() {
        Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { [weak self] in await self?.refreshEntitlements() }
    }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.premiumProductID]).first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase() async {
        guard let product else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-checks StoreKit's records — covers a reinstall or a new device,
    /// since a non-consumable has no receipt stored locally to fall back on.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        for await entitlement in Transaction.currentEntitlements {
            await handle(entitlement)
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.premiumProductID else { return }
        isPremium = transaction.revocationDate == nil
        await transaction.finish()
    }
}
