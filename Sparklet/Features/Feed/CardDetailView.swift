import SwiftUI

// Standalone single-card screen, reached by tapping a related-card link in
// CardView's 🧭 menu — closes AGENTS.md's "Still open" #10 (that menu was
// informational-only because no card-detail screen existed to link to).
// Presented as a `.sheet`, matching every other secondary screen in this
// app (Comments/Report/FullCard/Notifications/etc. are all sheets, not
// NavigationStack pushes) — a related card tapped from *within* this
// screen opens another CardDetailView the same way, via a locally scoped
// Identifiable route so sheets can chain to an arbitrary depth.
//
// Action-rail state/logic (vote/save/depth-switch/comments/report) is
// deliberately duplicated from CardView rather than extracted into a
// shared component: the two screens' layouts differ enough (CardView's
// rail is a floating corner overlay sized for one fixed feed page;
// this one is a plain scrolling column with room to spare) that a shared
// component would need almost as much layout-specific plumbing as it'd
// save, for exactly two call sites.
struct CardDetailView: View {
    let cardId: String
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var card: FeedCard?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var score = 0
    @State private var myVote = 0
    @State private var saved = false
    @State private var commentCount = 0
    @State private var displayedTitle = ""
    @State private var displayedBody = ""
    @State private var currentLevel: DepthLevel = .standard
    @State private var depthLoading: DepthLevel?
    @State private var depthUnavailable = false
    @State private var variantCache: [DepthLevel: (title: String, body: String)] = [:]

    @State private var showingComments = false
    @State private var showingReport = false
    @State private var showingUpgrade = false
    @State private var relatedRoute: RelatedRoute?

    private let api = CardActionsAPI()

    var body: some View {
        NavigationStack {
            Group {
                if let card {
                    content(for: card)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .foregroundStyle(Theme.accentText)
                    }
                    .padding()
                } else {
                    ProgressView().tint(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .sheet(isPresented: $showingComments) {
            if let card {
                CommentsSheetView(
                    cardId: card.id,
                    cardTitle: displayedTitle,
                    authSession: authSession,
                    onCountChange: { commentCount = $0 }
                )
            }
        }
        .sheet(isPresented: $showingReport) {
            if let card {
                ReportSheetView(target: .card(id: card.id), authSession: authSession) {
                    showingReport = false
                }
            }
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView(purchaseManager: purchaseManager)
        }
        .sheet(item: $relatedRoute) { route in
            CardDetailView(cardId: route.id)
        }
    }

    @ViewBuilder
    private func content(for card: FeedCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(card.category.icon) \(card.category.name)")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hexString: card.category.colorHex))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(hexString: card.category.colorHex).opacity(0.2), in: Capsule())
                    Spacer()
                }

                if let imageUrl = card.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Theme.panelAlt
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text(displayedTitle)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)

                Text(displayedBody)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)

                if let firstSource = card.sources.first, let sourceURL = URL(string: firstSource.url) {
                    Link(firstSource.publisher, destination: sourceURL)
                        .font(.caption)
                        .foregroundStyle(Theme.accentText)
                }

                actionRow

                if !card.related.isEmpty {
                    relatedSection(card.related)
                }
            }
            .padding()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            voteControl
            if !depthUnavailable {
                depthMenu
            }
            commentsButton
            saveButton
            shareLink
            reportButton
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var voteControl: some View {
        HStack(spacing: 6) {
            Button {
                Task { await vote(1) }
            } label: {
                Text("▲").font(.headline)
            }
            .foregroundStyle(myVote == 1 ? Theme.success : Theme.textTertiary)

            Text("\(score)")
                .font(.caption.bold())
                .foregroundStyle(score > 0 ? Theme.successText : score < 0 ? Theme.dangerText : Theme.textSecondary)

            Button {
                Task { await vote(-1) }
            } label: {
                Text("▼").font(.headline)
            }
            .foregroundStyle(myVote == -1 ? Theme.dangerText : Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panelAlt.opacity(0.8), in: Capsule())
    }

    private var depthIcon: String {
        switch currentLevel {
        case .simple: return "✨"
        case .standard: return "📖"
        case .deep: return "🔬"
        case .extraDeep: return "📚"
        }
    }

    private func depthLabel(_ level: DepthLevel) -> String {
        switch level {
        case .simple: return "Simpler"
        case .standard: return "Standard"
        case .deep: return "Go deeper"
        case .extraDeep: return "Extra deep"
        }
    }

    private func isLocked(_ level: DepthLevel) -> Bool {
        (level == .deep || level == .extraDeep) && !purchaseManager.premium
    }

    private var depthMenu: some View {
        Menu {
            ForEach(DepthLevel.allCases.filter { $0 != currentLevel }, id: \.self) { level in
                if isLocked(level) {
                    Button {
                        showingUpgrade = true
                    } label: {
                        Label("\(depthLabel(level)) — Premium", systemImage: "lock.fill")
                    }
                } else {
                    Button(depthLabel(level)) {
                        Task { await chooseDepth(level) }
                    }
                }
            }
        } label: {
            railIcon(depthLoading != nil ? "hourglass" : nil, emoji: depthLoading == nil ? depthIcon : nil)
        }
    }

    private var commentsButton: some View {
        Button {
            showingComments = true
        } label: {
            VStack(spacing: 0) {
                Text("💬").font(.headline)
                if commentCount > 0 {
                    Text("\(commentCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 40, height: 40)
            .background(Theme.panelAlt.opacity(0.7), in: Circle())
        }
    }

    private var saveButton: some View {
        Button {
            Task { await toggleSave() }
        } label: {
            railIcon(nil, emoji: saved ? "🔖" : "📑")
        }
        .opacity(saved ? 1 : 0.7)
    }

    private var shareLink: some View {
        ShareLink(item: AppConfig.apiBaseURL.appendingPathComponent("card/\(cardId)")) {
            railIcon(nil, emoji: "📤")
        }
        .opacity(0.7)
    }

    private var reportButton: some View {
        Button {
            showingReport = true
        } label: {
            railIcon(nil, emoji: "⚑")
        }
        .foregroundStyle(Theme.textMuted)
    }

    private func railIcon(_ systemImage: String?, emoji: String?) -> some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
            } else if let emoji {
                Text(emoji)
            }
        }
        .font(.headline)
        .frame(width: 40, height: 40)
        .background(Theme.panelAlt.opacity(0.7), in: Circle())
        .foregroundStyle(Theme.textPrimary)
    }

    private func relatedSection(_ related: [RelatedLink]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(Theme.border)
            Text("Connects to")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 8)
            ForEach(related, id: \.id) { link in
                Button {
                    relatedRoute = RelatedRoute(id: link.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(link.icon)
                        Text(link.title)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await api.fetchCard(cardId: cardId, token: authSession.token)
            card = fetched
            score = fetched.score
            myVote = fetched.myVote
            saved = fetched.saved
            commentCount = fetched.commentCount
            displayedTitle = fetched.title
            displayedBody = fetched.body
            currentLevel = .standard
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            errorMessage = "Couldn't load this card."
        }
        isLoading = false
    }

    private func vote(_ value: Int) async {
        let next = myVote == value ? 0 : value
        let previousVote = myVote
        let previousScore = score
        myVote = next
        score += next - previousVote
        do {
            let response = try await api.vote(cardId: cardId, value: next, token: authSession.token)
            score = response.score
            myVote = response.myVote
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            myVote = previousVote
            score = previousScore
        }
    }

    private func toggleSave() async {
        let next = !saved
        saved = next
        do {
            let response = try await api.setSaved(cardId: cardId, saved: next, token: authSession.token)
            saved = response.saved
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            saved = !next
        }
    }

    private func chooseDepth(_ target: DepthLevel) async {
        guard let card else { return }
        if target == .standard {
            currentLevel = .standard
            displayedTitle = card.title
            displayedBody = card.body
            return
        }
        if let cached = variantCache[target] {
            currentLevel = target
            displayedTitle = cached.title
            displayedBody = cached.body
            return
        }
        guard depthLoading == nil else { return }
        depthLoading = target
        defer { depthLoading = nil }
        do {
            let response = try await api.fetchDepth(cardId: cardId, level: target, token: authSession.token)
            variantCache[target] = (response.card.title, response.card.body)
            currentLevel = target
            displayedTitle = response.card.title
            displayedBody = response.card.body
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch APIError.server(let status, _) where status == 503 {
            depthUnavailable = true
        } catch {
            // Leave whatever was showing — including a 402 race if premium
            // expired between the menu rendering and this tap.
        }
    }
}

private struct RelatedRoute: Identifiable {
    let id: String
}
