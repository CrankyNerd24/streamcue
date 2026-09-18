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

    static let premiumProductID = "com.CrankyNerdNew.StreamCue.premium"

    /// Local record of grandfathering, so a confirmed grandfathered user
    /// never needs another CloudKit round trip to prove it again.
    private static let grandfatheredKey = "grandfatheredPremium"

    private(set) var isPremium = false
    private(set) var product: Product?
    private(set) var isWorking = false
    var errorMessage: String?

    // `shared` lives for the app's whole lifetime, so this task is never
    // cancelled — there's no deinit to do it from.
    private init() {
        if UserDefaults.standard.bool(forKey: Self.grandfatheredKey) {
            isPremium = true
        }
        Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { [weak self] in await self?.refreshEntitlements() }
        Task { [weak self] in await self?.checkGrandfathering() }
    }

    /// Anyone who already had household sharing or automatic Reminders sync
    /// before this build introduced the paywall keeps them for free. Both
    /// are gated behind `isPremium` everywhere they can be turned on, so
    /// either one being true here can only mean it was set before the gate
    /// existed — never a false positive after the fact.
    private func checkGrandfathering() async {
        guard !isPremium else { return }
        let hadAutoReminders = UserDefaults.standard.bool(forKey: ReminderSync.autoKey)
        let hadHousehold = await HouseholdShareManager.ownsShare()
        guard hadAutoReminders || hadHousehold else { return }
        isPremium = true
        UserDefaults.standard.set(true, forKey: Self.grandfatheredKey)
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
