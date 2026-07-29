import SwiftUI
import StoreKit

// Mirrors the web's /upgrade page, but through StoreKit 2 In-App Purchase
// rather than Stripe Checkout — App Store Review Guideline 3.1.1 requires
// digital subscriptions unlocking in-app content go through StoreKit, not a
// link to an external checkout (see AGENTS.md's "Decisions made"). Premium
// is a single account-wide flag shared with the web (GET /api/profile/
// details' `premium`, backed by src/lib/billing.ts's isPremium() on the
// backend) — subscribing here also unlocks the web's ad-free/Deeper-reading
// benefits on the same account.
struct UpgradeView: View {
    @ObservedObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingManageSubscriptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("✨ Sparklet Premium")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("No ads, and unlimited Deeper / Extra-deep reading on every card. Cancel anytime.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)

                    if purchaseManager.premium {
                        premiumCard
                    } else if purchaseManager.isLoadingProducts, purchaseManager.products.isEmpty {
                        ProgressView().tint(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if purchaseManager.products.isEmpty {
                        Text("Premium isn't available yet — check back soon.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        ForEach(purchaseManager.products) { product in
                            planCard(product)
                        }
                    }

                    Button("Restore purchases") {
                        Task { await purchaseManager.restore() }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding()
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
        }
    }

    private var premiumCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✨ You're Premium")
                .font(.headline)
                .foregroundStyle(Theme.accentText)
            Text("Ads are off and Deeper / Extra-deep reading is unlocked on every card.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
            Button("Manage subscription") {
                showingManageSubscriptions = true
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }

    private func planCard(_ product: Product) -> some View {
        let isAnnual = product.id == PurchaseManager.annualID
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(product.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                if isAnnual {
                    Text("BEST VALUE")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.2), in: Capsule())
                }
            }
            Text(product.displayPrice)
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
            Button {
                Task { await purchaseManager.purchase(product) }
            } label: {
                if purchaseManager.isPurchasing {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Subscribe")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .disabled(purchaseManager.isPurchasing)
        }
        .padding()
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }
}
