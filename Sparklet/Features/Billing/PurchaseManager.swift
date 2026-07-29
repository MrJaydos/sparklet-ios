import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let monthlyID = "com.sparklet.ios.premium.monthly"
    static let annualID = "com.sparklet.ios.premium.annual"

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var premium = false
    @Published private(set) var expiresAt: Date?

    private let api = BillingAPI()
    private let authSession: AuthSession
    private var updatesTask: Task<Void, Never>?

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: [Self.monthlyID, Self.annualID])
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            // Best-effort — the Upgrade screen just shows no plans.
        }
    }

    // Starts the app-wide listener exactly once (called from SparkletApp at
    // launch) — catches renewals/refunds that complete when the purchase
    // flow itself isn't open, same role as a webhook but client-side.
    func startListeningForTransactionUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // Best-effort — the screen just stays on the plan picker.
        }
    }

    // Walks currently active entitlements and re-reconciles each with the
    // server — self-corrects `premium` on every Upgrade screen visit
    // without needing a manual restore, since Transaction.updates only
    // fires for new events, not a full replay of history on each launch.
    // Harmless to re-verify something already reconciled.
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            await handle(result)
        }
    }

    // Forces a fresh sync with the App Store first — for the explicit
    // "Restore purchases" button, where a network round-trip (and a
    // possible system sign-in prompt) is expected, unlike the passive
    // refreshEntitlements() above.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        await transaction.finish()
        do {
            let response = try await api.verify(
                signedTransactionInfo: verification.jwsRepresentation,
                token: authSession.token
            )
            premium = response.premium
            expiresAt = response.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the server can reconcile this transaction again
            // next time Transaction.currentEntitlements/updates delivers it.
        }
    }
}
