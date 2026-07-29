import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api = FeedAPI()
    private let answersAPI = AnswersAPI()
    private let authSession: AuthSession

    // Cumulative pools behind `items` — kept separately because interleaving
    // is recomputed from scratch over everything loaded so far every time a
    // new batch arrives (see rebuildItems), same as Feed.tsx's `items`
    // useMemo recomputing over its full accumulated state each render.
    private var cards: [FeedCard] = []
    private var quizzes: [FeedQuiz] = []
    private var reviewQuizzes: [FeedReviewQuiz] = []
    private var guesses: [FeedGuess] = []
    private var misconceptions: [FeedMisconception] = []
    private var explainPrompts: [FeedExplainPrompt] = []

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
            quizzes = response.quizzes
            reviewQuizzes = response.reviewQuizzes
            guesses = response.guesses
            misconceptions = response.misconceptions
            explainPrompts = response.explainPrompts
            rebuildItems()
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            errorMessage = "Couldn't load the feed. Pull to retry."
        }
    }

    // Pagination: appends the next batch once the visible item nears the
    // end of what's loaded, excluding card ids already shown. Same
    // excludeIds approach the web client uses for its session-seen set
    // (Feed.tsx) — inherits the same eventual URL-length ceiling on very
    // long sessions, not something to solve here without a matching backend
    // change. Gated on position within `items`, not `cards` — the visible
    // item may be a quiz/guess/etc. sitting between cards, and it still
    // needs to trigger a load if it's near the tail of everything loaded.
    func loadMoreIfNeeded(visibleItemId: String) async {
        guard !isLoading, let index = items.firstIndex(where: { $0.id == visibleItemId }) else { return }
        guard index >= items.count - 2 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.fetchFeed(
                take: 10,
                excludeIds: cards.map(\.id),
                token: authSession.token
            )
            cards.append(contentsOf: response.cards)
            quizzes.append(contentsOf: response.quizzes)
            reviewQuizzes.append(contentsOf: response.reviewQuizzes)
            guesses.append(contentsOf: response.guesses)
            misconceptions.append(contentsOf: response.misconceptions)
            explainPrompts.append(contentsOf: response.explainPrompts)
            rebuildItems()
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the user can still scroll what's already loaded.
        }
    }

    private func rebuildItems() {
        items = Self.buildItems(
            cards: cards,
            quizzes: quizzes,
            reviewQuizzes: reviewQuizzes,
            guesses: guesses,
            misconceptions: misconceptions,
            explainPrompts: explainPrompts
        )
    }

    private static let quizEvery = 10
    private static let guessEvery = 12
    private static let guessOffset = 1
    private static let misconceptionEvery = 10
    private static let misconceptionOffset = 2
    private static let explainEvery = 12
    private static let explainOffset = 3

    // Ports Feed.tsx's exact interleave offsets: quiz lands on card 10, 20,
    // 30…; guess on 1, 13, 25…; misconception on 2, 12, 22…; explain on
    // 3, 15, 27… — chosen so none collide. reviewQuizzes instead get an
    // even spread across the whole card count (same shape as the
    // server-side interleave() in sparklet/src/lib/feed.ts, reimplemented
    // here since reviewQuizzes themselves arrive as a flat, un-positioned
    // array) rather than a fixed period, then flush just before the card
    // at their computed position.
    //
    // `nonisolated` — pure function over its arguments, no FeedViewModel
    // instance state touched, so it shouldn't inherit the class's
    // @MainActor isolation. Lets FeedItemInterleaveTests call it from a
    // plain synchronous (non-MainActor) test method.
    nonisolated static func buildItems(
        cards: [FeedCard],
        quizzes: [FeedQuiz],
        reviewQuizzes: [FeedReviewQuiz],
        guesses: [FeedGuess],
        misconceptions: [FeedMisconception],
        explainPrompts: [FeedExplainPrompt]
    ) -> [FeedItem] {
        var result: [FeedItem] = []
        var quizCursor = 0
        var guessCursor = 0
        var misconceptionCursor = 0
        var explainCursor = 0
        var reviewQuizCursor = 0

        let reviewQuizPositions = reviewQuizzes.indices.map { i in
            Int((Double(i + 1) * Double(cards.count) / Double(reviewQuizzes.count + 1)).rounded())
        }

        for (i, card) in cards.enumerated() {
            let position = i + 1
            while reviewQuizCursor < reviewQuizzes.count, reviewQuizPositions[reviewQuizCursor] <= position {
                result.append(.reviewQuiz(reviewQuizzes[reviewQuizCursor]))
                reviewQuizCursor += 1
            }
            result.append(.card(card))
            if position % quizEvery == 0, quizCursor < quizzes.count {
                result.append(.quiz(quizzes[quizCursor]))
                quizCursor += 1
            }
            if position % guessEvery == guessOffset, guessCursor < guesses.count {
                result.append(.guess(guesses[guessCursor]))
                guessCursor += 1
            }
            if position % misconceptionEvery == misconceptionOffset, misconceptionCursor < misconceptions.count {
                result.append(.misconception(misconceptions[misconceptionCursor]))
                misconceptionCursor += 1
            }
            if position % explainEvery == explainOffset, explainCursor < explainPrompts.count {
                result.append(.explain(explainPrompts[explainCursor]))
                explainCursor += 1
            }
        }
        while reviewQuizCursor < reviewQuizzes.count {
            result.append(.reviewQuiz(reviewQuizzes[reviewQuizCursor]))
            reviewQuizCursor += 1
        }
        return result
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

    // Answer calls below all share the same shape: sign out on 401 (mirrors
    // load()/trackView), otherwise swallow the error and return nil so the
    // view's optimistic "submitting" state just resets — a failed answer
    // POST loses that one attempt's feedback/XP, nothing worse, and the
    // user can't retry a first-answer-stands endpoint anyway.
    func answerQuiz(id: String, index: Int) async -> QuizAnswerResponse? {
        do {
            return try await answersAPI.answerQuiz(id: id, index: index, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
            return nil
        } catch {
            return nil
        }
    }

    func answerReview(id: String, index: Int) async -> QuizAnswerResponse? {
        do {
            return try await answersAPI.answerReview(id: id, index: index, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
            return nil
        } catch {
            return nil
        }
    }

    func answerGuess(id: String, guess: Double) async -> GuessAnswerResponse? {
        do {
            return try await answersAPI.answerGuess(id: id, guess: guess, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
            return nil
        } catch {
            return nil
        }
    }

    func answerMisconception(id: String, guess: Bool) async -> MisconceptionAnswerResponse? {
        do {
            return try await answersAPI.answerMisconception(id: id, guess: guess, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
            return nil
        } catch {
            return nil
        }
    }

    func answerExplain(cardId: String, text: String) async -> ExplainAnswerResponse? {
        do {
            return try await answersAPI.answerExplain(cardId: cardId, text: text, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
            return nil
        } catch {
            return nil
        }
    }

    func skipExplain(cardId: String) async -> ExplainAnswerResponse? {
        do {
            return try await answersAPI.skipExplain(cardId: cardId, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
            return nil
        } catch {
            return nil
        }
    }
}
