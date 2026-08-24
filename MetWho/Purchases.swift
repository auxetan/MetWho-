import StoreKit
import Observation

/// MetWho Pro, for real this time.
///
/// The previous version of this screen set `prefs.pro = true` on tap — both from
/// "Continue" and from "Restore" — which is a rejection on sight and, worse, a
/// lie to anyone who paid attention. Entitlement now comes from StoreKit and
/// nowhere else: there is deliberately no way to set it from the app's own code,
/// so no future screen can accidentally grant it again.
///
/// `Transaction.currentEntitlements` is the source of truth on every launch, so
/// a lapsed subscription lapses without the app having to remember anything.
@MainActor
@Observable
final class Purchases {

    static let shared = Purchases()

    enum ProductID {
        static let monthly = "com.metwho.app.pro.monthly"
        static let yearly = "com.metwho.app.pro.yearly"
        static let all = [monthly, yearly]
    }

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var busy = false
    private(set) var failure: String?

    /// Never cancelled: this object is the singleton and outlives everything that
    /// could want to stop listening.
    private var updates: Task<Void, Never>?

    private init() {
        // a purchase can land while the app is backgrounded, or be approved by a
        // parent hours later; without this listener that money buys nothing
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self, case .verified(let t) = update else { continue }
                await t.finish()
                await self.refresh()
            }
        }
    }

    func load() async {
        await refresh()
        guard products.isEmpty else { return }
        products = ((try? await Product.products(for: ProductID.all)) ?? [])
            .sorted { $0.price < $1.price }
    }

    /// Recomputed rather than stored: the only honest answer to "is this person a
    /// subscriber" is whatever StoreKit says right now.
    func refresh() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            if ProductID.all.contains(t.productID), t.revocationDate == nil { entitled = true }
        }
        isPro = entitled
    }

    func buy(_ product: Product) async {
        guard !busy else { return }
        busy = true
        failure = nil
        defer { busy = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else {
                    failure = "That purchase could not be verified."
                    return
                }
                await t.finish()
                await refresh()
            case .userCancelled:
                break
            case .pending:
                // Ask to Buy and similar: the listener above picks it up later
                failure = "Waiting on approval. Pro turns on by itself once it clears."
            @unknown default:
                break
            }
        } catch {
            failure = "The purchase did not go through."
        }
    }

    /// Restores by asking the App Store to re-sync, then re-reading entitlements.
    /// It cannot grant anything on its own, which is the point.
    func restore() async {
        guard !busy else { return }
        busy = true
        failure = nil
        defer { busy = false }

        try? await AppStore.sync()
        await refresh()
        if !isPro { failure = "No subscription found on this Apple Account." }
    }
}

extension Product {
    /// "4,99 € / month" in the user's own locale and currency.
    var priceLine: String {
        guard let period = subscription?.subscriptionPeriod else { return displayPrice }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 7 ? "week" : "day"
        case .week: unit = "week"
        case .month: unit = period.value == 12 ? "year" : "month"
        case .year: unit = "year"
        @unknown default: return displayPrice
        }
        return "\(displayPrice) / \(unit)"
    }
}
