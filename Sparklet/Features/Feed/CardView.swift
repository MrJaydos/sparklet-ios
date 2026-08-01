import SwiftUI
import UIKit

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
    // Whether this specific card is the one actually centered on screen —
    // mirrors LearnCard.tsx's IntersectionObserver(threshold: 0.6), which
    // fires the remembered-depth auto-apply only once a card is genuinely
    // in view, not merely instantiated (SwiftUI's LazyVStack keeps a couple
    // of off-screen cards alive too; auto-applying for those would be the
    // same "claiming something that isn't true" integrity problem
    // FeedView's read-tracking comment already flags for view-dwell).
    let isVisible: Bool
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
    @State private var showingFullCard = false
    @State private var relatedRoute: RelatedCardRoute?
    @State private var cardWidth: CGFloat = 0
    // Fire-once guard for the auto-apply effect below — same "per-view, so
    // a fast scroll doesn't fire a generation for every card" semantics as
    // the web's observer.disconnect() after its first trigger.
    @State private var hasAutoAppliedDepthPreference = false

    // A card fills exactly one page and a photo eats into that budget, so a
    // card with an image gets a tighter line limit than a text-only one.
    private var maxBodyLines: Int { card.imageUrl != nil ? 6 : 10 }

    // Whether maxBodyLines actually cut something off, so "Read more" only
    // shows up when there's something to read more of. A SwiftUI
    // background()+fixedSize() height-comparison trick was tried first and
    // measured wrong live (a `.background()` is sized to fit its host, so a
    // "natural size" child inside one can't be trusted to report its own
    // unconstrained height) — this instead measures with UIKit's
    // NSString.boundingRect directly against the card's actual on-screen
    // width, sidestepping that SwiftUI layout ambiguity entirely.
    private var isBodyTruncated: Bool {
        guard cardWidth > 0 else { return false }
        // 32 = the outer content VStack's default .padding(); 56 = the
        // body Text's own .padding(.trailing, 56) that keeps it clear of
        // the action rail — both subtracted to get the Text's real width.
        let width = max(cardWidth - 32 - 56, 0)
        let font = UIFont.preferredFont(forTextStyle: .body)
        let fullHeight = (displayedBody as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        let limitedHeight = CGFloat(maxBodyLines) * font.lineHeight
        return fullHeight > limitedHeight + 1
    }

    private let api = CardActionsAPI()

    init(card: FeedCard, isVisible: Bool) {
        self.card = card
        self.isVisible = isVisible
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
        // parent captures the drag gesture and breaks paging. Fixed instead
        // by capping the body to maxBodyLines and, only when that actually
        // truncated something (isBodyTruncated below — not a character-count
        // guess, which could under-truncate and silently hide content
        // again), surfacing a "Read more" button that opens the untruncated
        // card in a sheet. A sheet is presented above
        // the feed with its own independent gesture space, so it can't
        // conflict with the paging ScrollView the way a nested one did.
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
                    .lineLimit(maxBodyLines)

                if isBodyTruncated {
                    Button("Read more") { showingFullCard = true }
                        .font(.footnote.bold())
                        .foregroundStyle(Theme.accentText)
                }

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
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { cardWidth = geo.size.width }
            }
        )
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
        .sheet(isPresented: $showingFullCard) {
            FullCardSheetView(card: card, title: displayedTitle, bodyText: displayedBody)
        }
        .sheet(item: $relatedRoute) { route in
            CardDetailView(cardId: route.id)
        }
        .task(id: isVisible) {
            await autoApplyDepthPreferenceIfNeeded()
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
                // Opens CardDetailView for the tapped related card — see
                // AGENTS.md's "Still open" #10, now closed: this menu was
                // informational-only until that screen existed to link to.
                ForEach(card.related, id: \.id) { link in
                    Button("\(link.icon) \(link.title)") {
                        relatedRoute = RelatedCardRoute(id: link.id)
                    }
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

    // A manual tap is also a preference — mirrors LearnCard.tsx's
    // chooseDepth: remember it (DepthPreference) so future cards auto-apply
    // it as they scroll into view, then apply it to this card the same way
    // the auto-apply path does.
    private func chooseDepth(_ target: DepthLevel) async {
        DepthPreference.set(target)
        await applyDepth(target)
    }

    // The auto-apply path calls this directly, skipping the preference
    // write — mirrors the web's `setDepthRef.current(pref)` call, which
    // reads the stored preference but deliberately doesn't re-write it.
    private func applyDepth(_ target: DepthLevel) async {
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

    // Mirrors LearnCard.tsx's IntersectionObserver effect: once this card is
    // actually visible, auto-apply a remembered SIMPLE/DEEP/EXTRA_DEEP
    // preference — nil (never set) or .standard (explicitly reset) both
    // mean "leave it alone", same as the web's early-return. A lapsed
    // subscriber's saved DEEP/EXTRA_DEEP preference must not silently
    // 402-race on every card in their feed, so this reuses the exact same
    // isLocked gate the manual menu already applies, not a separate check
    // that could drift from it.
    private func autoApplyDepthPreferenceIfNeeded() async {
        guard isVisible, !hasAutoAppliedDepthPreference else { return }
        hasAutoAppliedDepthPreference = true
        guard let pref = DepthPreference.get(), pref != .standard, !isLocked(pref) else { return }
        await applyDepth(pref)
    }
}

// The untruncated escape hatch for CardView's "Read more" — a plain
// non-paging ScrollView, safe here because a sheet sits above the feed in
// its own gesture space rather than nesting inside .scrollTargetBehavior(.paging).
private struct FullCardSheetView: View {
    let card: FeedCard
    let title: String
    let bodyText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(card.category.icon) \(card.category.name)")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.panelAlt, in: Capsule())

                    if let imageUrl = card.imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Theme.panelAlt
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.textPrimary)

                    Text(bodyText)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)

                    if let firstSource = card.sources.first, let sourceURL = URL(string: firstSource.url) {
                        Link(firstSource.publisher, destination: sourceURL)
                            .font(.caption)
                            .foregroundStyle(Theme.accentText)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Full card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct RelatedCardRoute: Identifiable {
    let id: String
}
