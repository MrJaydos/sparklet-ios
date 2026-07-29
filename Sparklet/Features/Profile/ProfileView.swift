import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    let authSession: AuthSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapViewModel: KnowledgeMapViewModel
    @State private var showingMap = false

    private static let statColumns = [GridItem(.flexible()), GridItem(.flexible())]
    private static let badgeColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    init(viewModel: ProfileViewModel, authSession: AuthSession) {
        self.viewModel = viewModel
        self.authSession = authSession
        _mapViewModel = StateObject(wrappedValue: KnowledgeMapViewModel(authSession: authSession))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading, viewModel.details == nil {
                    ProgressView().tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let details = viewModel.details {
                    VStack(alignment: .leading, spacing: 24) {
                        header(details)
                        statsGrid(details)
                        freezeAndReviewsCaption(details)
                        inviteRow(details)
                        knowledgeMapRow(details)
                        badgesSection(details)
                        topTopicsSection(details)
                        notebookSection(details)
                        historySection(details)
                    }
                    .padding()
                }
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Profile")
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
        .sheet(isPresented: $showingMap) {
            KnowledgeMapView(viewModel: mapViewModel)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private func knowledgeMapRow(_ details: ProfileDetailsResponse) -> some View {
        Button {
            showingMap = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🗺️ Your knowledge map")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("See \(details.totalViewed) learned facts as a growing constellation")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
    }

    private func header(_ details: ProfileDetailsResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(details.email)
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
            HStack {
                TextField("Set a display name", text: $viewModel.name)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                Button {
                    Task { await viewModel.saveName() }
                } label: {
                    if viewModel.isSavingName {
                        ProgressView().tint(Theme.textTertiary)
                    } else {
                        Text("Save")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                .disabled(viewModel.isSavingName)
            }
        }
    }

    private func statsGrid(_ details: ProfileDetailsResponse) -> some View {
        LazyVGrid(columns: Self.statColumns, spacing: 12) {
            statTile(value: "\(details.totalViewed)", label: "cards learned")
            statTile(value: "⚡ \(details.xp)", label: "lifetime XP", tint: .yellow)
            statTile(value: "🔥 \(details.currentStreak)", label: "day streak", tint: .orange)
            statTile(value: "\(details.longestStreak)", label: "longest streak")
        }
    }

    private func statTile(value: String, label: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }

    private func freezeAndReviewsCaption(_ details: ProfileDetailsResponse) -> some View {
        let freezeText = "🧊 \(details.freezesAvailable) streak freeze\(details.freezesAvailable == 1 ? "" : "s") available"
        let reviewsText = details.dueReviews > 0
            ? " · 🔁 \(details.dueReviews) card\(details.dueReviews == 1 ? "" : "s") due for review"
            : ""
        return Text(freezeText + reviewsText)
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
    }

    // Mirrors the web hamburger menu's "Invite friends" share action
    // (src/components/feed/MenuSheet.tsx) — a friend who signs up through
    // this link auto-friends the sharer and, on their first-ever session,
    // grants the sharer a bonus streak freeze (POST /api/invite/[refId]/
    // accept, InviteView).
    private func inviteRow(_ details: ProfileDetailsResponse) -> some View {
        let url = AppConfig.apiBaseURL.appendingPathComponent("invite/\(details.id)")
        return ShareLink(item: url, subject: Text("Join me on Sparklet"), message: Text("Learn something real, one swipe at a time.")) {
            HStack {
                Label("Invite friends", systemImage: "gift.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
    }

    private func badgesSection(_ details: ProfileDetailsResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badges").font(.headline).foregroundStyle(Theme.textPrimary)
            LazyVGrid(columns: Self.badgeColumns, spacing: 8) {
                ForEach(details.badges) { badge in
                    VStack(spacing: 4) {
                        Text(badge.icon)
                            .font(.title3)
                            .opacity(badge.earnedTier == nil ? 0.3 : 1)
                        Text(badge.earnedTier?.label ?? badge.name)
                            .font(.caption.bold())
                            .foregroundStyle(badge.earnedTier == nil ? Theme.textMuted : .yellow)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(badge.nextTier.map { "\(badge.value)/\($0.threshold)" } ?? "maxed")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        badge.earnedTier == nil ? Theme.panel : Color.yellow.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(badge.earnedTier == nil ? Theme.border : Color.yellow.opacity(0.4))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func topTopicsSection(_ details: ProfileDetailsResponse) -> some View {
        if !details.topCategories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top topics").font(.headline).foregroundStyle(Theme.textPrimary)
                FlowLayout(spacing: 8) {
                    ForEach(details.topCategories, id: \.name) { category in
                        let tint = Color(hexString: category.colorHex)
                        Text("\(category.icon) \(category.name) · \(category.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func notebookSection(_ details: ProfileDetailsResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notebook").font(.headline).foregroundStyle(Theme.textPrimary)
            if details.savedCards.isEmpty {
                Text("Tap the save icon on a card to add it to your notebook — your deliberate keep-list.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(details.savedCards) { card in
                        cardRow(icon: card.icon, colorHex: card.colorHex, title: card.title)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func historySection(_ details: ProfileDetailsResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline).foregroundStyle(Theme.textPrimary)
            if details.history.isEmpty {
                Text("Every card you view ends up here, so nothing is ever lost to a scroll or a refresh.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(details.history.enumerated()), id: \.offset) { _, entry in
                        cardRow(icon: entry.icon, colorHex: entry.colorHex, title: entry.title, when: entry.when)
                    }
                }
            }
        }
    }

    private func cardRow(icon: String, colorHex: String, title: String, when: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.caption)
                .foregroundStyle(Color(hexString: colorHex))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            if let when {
                Spacer()
                Text(when)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 6)
    }
}
