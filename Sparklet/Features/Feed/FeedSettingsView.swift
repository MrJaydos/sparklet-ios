import SwiftUI

// Mirrors CategorySheet.tsx's "Your feed" sheet — topic filter, reading
// depth preference, and daily card-count goal, all in one place, same as
// the web bundles them. Topic filtering itself (GET /api/feed's `categories`
// param, GET /api/categories) already existed client-side with zero UI to
// drive it; depth/goal preferences (DepthPreference/DailyCardGoal) already
// had backing logic from earlier passes but no way to change them either —
// this sheet is what was actually missing, not new plumbing underneath it.
struct FeedSettingsView: View {
    let authSession: AuthSession
    let purchaseManager: PurchaseManager
    let selected: [String]
    let onApply: ([String]) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [Category] = []
    @State private var isLoadingCategories = true
    @State private var picked: [String]
    @State private var depth: DepthLevel
    @State private var goal: Int
    @State private var showingUpgrade = false
    @State private var isApplying = false

    private let api = OnboardingAPI()
    private static let columns = [GridItem(.flexible()), GridItem(.flexible())]

    init(authSession: AuthSession, purchaseManager: PurchaseManager, selected: [String], onApply: @escaping ([String]) async -> Void) {
        self.authSession = authSession
        self.purchaseManager = purchaseManager
        self.selected = selected
        self.onApply = onApply
        _picked = State(initialValue: selected)
        _depth = State(initialValue: DepthPreference.get() ?? .standard)
        _goal = State(initialValue: DailyCardGoal.current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pick topics, or select none for everything.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        everythingButton

                        if isLoadingCategories {
                            ProgressView().tint(Theme.textTertiary).frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: Self.columns, spacing: 8) {
                                ForEach(categories, id: \.slug) { category in
                                    categoryChip(category)
                                }
                            }
                        }
                    }

                    depthSection
                    goalSection
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Your feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(applyLabel) {
                        Task {
                            isApplying = true
                            await onApply(picked)
                            isApplying = false
                            dismiss()
                        }
                    }
                    .disabled(isApplying)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            categories = (try? await api.fetchCategories(token: authSession.token)) ?? []
            isLoadingCategories = false
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView(purchaseManager: purchaseManager)
        }
    }

    private var applyLabel: String {
        picked.isEmpty ? "Show everything" : "Show \(picked.count)"
    }

    private var everythingButton: some View {
        Button {
            picked = []
        } label: {
            HStack {
                Text("🎲 Random / Everything").font(.subheadline.bold())
                Spacer()
            }
            .padding()
            .background(
                picked.isEmpty ? Theme.accent.opacity(0.2) : Theme.panel,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(picked.isEmpty ? Theme.accent : Theme.border)
            )
        }
        .foregroundStyle(picked.isEmpty ? Theme.accentText : Theme.textPrimary)
    }

    private func categoryChip(_ category: Category) -> some View {
        let active = picked.contains(category.slug)
        let tint = Color(hexString: category.colorHex)
        return Button {
            if active {
                picked.removeAll { $0 == category.slug }
            } else {
                picked.append(category.slug)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.icon).font(.title3)
                Text(category.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(active ? tint.opacity(0.25) : Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? tint : Theme.border))
        }
    }

    // MARK: - Reading depth

    private struct DepthOption {
        let level: DepthLevel
        let label: String
        let blurb: String
    }

    private static let depthOptions: [DepthOption] = [
        DepthOption(level: .simple, label: "✨ Simpler", blurb: "plain-English takes"),
        DepthOption(level: .standard, label: "📖 Standard", blurb: "the card as written"),
        DepthOption(level: .deep, label: "🔬 Deeper", blurb: "more detail"),
        DepthOption(level: .extraDeep, label: "📚 Extra deep", blurb: "mini-articles"),
    ]

    private func isLocked(_ level: DepthLevel) -> Bool {
        (level == .deep || level == .extraDeep) && !purchaseManager.premium
    }

    private var depthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading depth").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("How much detail cards show — applies from the next card you scroll to.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Self.depthOptions, id: \.level) { option in
                    depthChip(option)
                }
            }
        }
    }

    private func depthChip(_ option: DepthOption) -> some View {
        let active = depth == option.level
        let locked = isLocked(option.level)
        return Button {
            if locked {
                showingUpgrade = true
            } else {
                depth = option.level
                DepthPreference.set(option.level)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(locked ? "🔒 \(option.label)" : option.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(active ? Theme.accentText : Theme.textSecondary)
                Text(locked ? "Premium — \(option.blurb)" : option.blurb)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(active ? Theme.accent.opacity(0.15) : Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? Theme.accent : Theme.border))
            .opacity(locked ? 0.7 : 1)
        }
    }

    // MARK: - Daily goal

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily goal").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Cards to hit each day before the feed celebrates and offers a break.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                ForEach(DailyCardGoal.options, id: \.self) { n in
                    goalChip(n)
                }
            }
        }
    }

    private func goalChip(_ n: Int) -> some View {
        let active = goal == n
        return Button {
            goal = n
            DailyCardGoal.set(n)
        } label: {
            Text("\(n)")
                .font(.subheadline.bold())
                .foregroundStyle(active ? Theme.accentText : Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(active ? Theme.accent.opacity(0.15) : Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? Theme.accent : Theme.border))
        }
    }
}
