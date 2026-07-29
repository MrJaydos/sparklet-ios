import SwiftUI

// Ports LearnCard.tsx's action rail (vote/depth/related/comments/save/
// share/report) onto the existing boxed-panel card layout — see the
// scrollability comment below, unchanged from before this pass. All
// per-card state here (score/myVote/saved/commentCount/depth variant)
// is local, exactly mirroring LearnCard.tsx's own local useState: none of
// it writes back into FeedViewModel's cards array, matching the web,
// where a vote/save/depth-switch never touches the parent's `card` prop
// either.
struct CardView: View {
    let card: FeedCard
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @State private var score: Int
    @State private var myVote: Int
    @State private var saved: Bool
    @State private var commentCount: Int

    @State private var displayedTitle: String
    @State private var displayedBody: String
    @State private var currentLevel: DepthLevel = .standard
    @State private var depthLoading: DepthLevel?
    @State private var depthUnavailable = false
    @State private var variantCache: [DepthLevel: (title: String, body: String)] = [:]

    @State private var showingComments = false
    @State private var showingReport = false
    @State private var showingUpgrade = false

    private let api = CardActionsAPI()

    init(card: FeedCard) {
        self.card = card
        _score = State(initialValue: card.score)
        _myVote = State(initialValue: card.myVote)
        _saved = State(initialValue: card.saved)
        _commentCount = State(initialValue: card.commentCount)
        _displayedTitle = State(initialValue: card.title)
        _displayedBody = State(initialValue: card.body)
    }

    var body: some View {
        // Each card fills exactly one page (FeedView's .containerRelativeFrame),
        // but body length varies (~40-80 words, occasionally more) and the
        // page height doesn't. A nested ScrollView here was tried and
        // reverted — a vertical scroll inside a .scrollTargetBehavior(.paging)
        // parent captures the drag gesture and breaks paging, which isn't
        // verifiable without a device/simulator. Known layout gap for now
        // (see AGENTS.md): an unusually long card is clipped rather than
        // scrollable within its page.
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(card.category.icon) \(card.category.name)")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.panelAlt, in: Capsule())
                    Spacer()
                }

                if let imageUrl = card.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Theme.panelAlt
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text(displayedTitle)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.trailing, 56) // keep text clear of the action rail

                Text(displayedBody)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.trailing, 56)

                if let firstSource = card.sources.first, let sourceURL = URL(string: firstSource.url) {
                    Link(firstSource.publisher, destination: sourceURL)
                        .font(.caption)
                        .foregroundStyle(Theme.accentText)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()

            actionRail
                .padding(.trailing, 10)
                .padding(.bottom, 14)
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .sheet(isPresented: $showingComments) {
            CommentsSheetView(
                cardId: card.id,
                cardTitle: card.title,
                authSession: authSession,
                onCountChange: { commentCount = $0 }
            )
        }
        .sheet(isPresented: $showingReport) {
            ReportSheetView(target: .card(id: card.id), authSession: authSession) {
                showingReport = false
            }
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView(purchaseManager: purchaseManager)
        }
    }

    // MARK: - Action rail

    private var actionRail: some View {
        VStack(spacing: 10) {
            voteControl
            if !depthUnavailable {
                depthMenu
            }
            if !card.related.isEmpty {
                relatedMenu
            }
            commentsButton
            saveButton
            shareLink
            reportButton
        }
    }

    private var voteControl: some View {
        VStack(spacing: 2) {
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
        .padding(.vertical, 6)
        .frame(width: 44)
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

    @ViewBuilder
    private var relatedMenu: some View {
        Menu {
            Section("Connects to") {
                // No card-detail screen exists in iOS yet (see AGENTS.md), so
                // unlike the web these aren't navigable — shown for parity
                // with the web's "this connects to…" trail, not as links.
                ForEach(card.related, id: \.id) { link in
                    Text("\(link.icon) \(link.title)")
                }
            }
        } label: {
            railIcon(nil, emoji: "🧭")
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
            .frame(width: 44, height: 44)
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
        ShareLink(item: AppConfig.apiBaseURL.appendingPathComponent("card/\(card.id)")) {
            railIcon(nil, emoji: "📤")
        }
        .opacity(0.7)
    }

    private var reportButton: some View {
        Button {
            showingReport = true
        } label: {
            Text("⚑")
                .font(.subheadline)
                .frame(width: 36, height: 36)
                .background(Theme.panelAlt.opacity(0.5), in: Circle())
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
        .frame(width: 44, height: 44)
        .background(Theme.panelAlt.opacity(0.7), in: Circle())
        .foregroundStyle(Theme.textPrimary)
    }

    // MARK: - Actions

    private func vote(_ value: Int) async {
        let next = myVote == value ? 0 : value
        let previousVote = myVote
        let previousScore = score
        myVote = next
        score += next - previousVote
        do {
            let response = try await api.vote(cardId: card.id, value: next, token: authSession.token)
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
            let response = try await api.setSaved(cardId: card.id, saved: next, token: authSession.token)
            saved = response.saved
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            saved = !next
        }
    }

    // A manual tap is deliberate — same "keep whatever loaded, if anything"
    // philosophy as everything else here, just without the web's
    // remembered-preference auto-apply-to-future-cards behavior (that's a
    // client-side-only nicety, not core to the feature — see AGENTS.md).
    private func chooseDepth(_ target: DepthLevel) async {
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
            let response = try await api.fetchDepth(cardId: card.id, level: target, token: authSession.token)
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
