import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var cards: [FeedCard] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api = FeedAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func loadIfNeeded() async {
        guard cards.isEmpty else { return }
        await load()
    }

    // Initial load and pull-to-refresh both replace the batch outright —
    // the feed is server-composed and stateless per request (sparklet/
    // src/lib/feed.ts), so "refresh" means "give me a fresh read," not
    // "append more." (An earlier pass appended here, which combined badly
    // with .refreshable on a paged scroll view: the visible card never
    // changed, so nothing looked refreshed, while excludeIds grew without
    // bound — see loadMore below for where that trade is actually made.)
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await api.fetchFeed(take: 10, token: authSession.token)
            cards = response.cards
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            errorMessage = "Couldn't load the feed. Pull to retry."
        }
    }

    // Pagination: appends the next batch once the visible card nears the
    // end of what's loaded, excluding ids already shown. Same excludeIds
    // approach the web client uses for its session-seen set (Feed.tsx) —
    // inherits the same eventual URL-length ceiling on very long sessions,
    // not something to solve here without a matching backend change.
    func loadMoreIfNeeded(currentId: String) async {
        guard !isLoading, let index = cards.firstIndex(where: { $0.id == currentId }) else { return }
        guard index >= cards.count - 2 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.fetchFeed(
                take: 10,
                excludeIds: cards.map(\.id),
                token: authSession.token
            )
            cards.append(contentsOf: response.cards)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the user can still scroll what's already loaded.
        }
    }

    // The server only counts a card as read once a second POST lands
    // ≥4.5s after the first, by its own clock (MIN_READ_GAP_MS in
    // sparklet/src/app/api/interactions/route.ts) — dwellMs is informational,
    // never trusted. Scrolling away cancels this task before the sleep
    // completes; the entry POST already upserted the row so the card won't
    // repeat, it just earns no XP, same as a fast swipe server-side.
    //
    // Callers MUST only invoke this for the single card actually visible on
    // screen (see FeedView's visibleCardId tracking) — firing it for every
    // instantiated card fabricates reads for cards nobody looked at, since
    // the 4.5s gap elapses regardless of whether the user was looking.
    @discardableResult
    func trackView(cardId: String) async -> XpSummary? {
        do {
            _ = try await api.postInteraction(cardId: cardId, token: authSession.token)
            try await Task.sleep(nanoseconds: 4_700_000_000)
            let response = try await api.postInteraction(cardId: cardId, dwellMs: 5_000, token: authSession.token)
            return response.xp
        } catch is CancellationError {
            return nil // Expected on scroll-away — see comment above.
        } catch {
            return nil // Best-effort: a missed read ping costs this card's XP, nothing else.
        }
    }
}
