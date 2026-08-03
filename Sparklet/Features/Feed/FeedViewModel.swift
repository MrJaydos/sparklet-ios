import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api = FeedAPI()
    private let answersAPI = AnswersAPI()
    private let authSession: AuthSession
    private let purchaseManager: PurchaseManager

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

    // Once true, every subsequent pagination call asks the server for
    // allowRepeats — the account has genuinely seen every unseen/due card at
    // least once this session, and this is a TikTok-style feed meant to
    // scroll for hours, not a fixed deck that dead-ends. Mirrors the web's
    // own `exhausted` flag (sparklet/src/lib/feed.ts), except the web stops
    // and shows a "You're all caught up" button for the user to opt into
    // repeats manually — this client opts in automatically instead, since an
    // endless feed is the whole product shape here.
    private var exhausted = false

    // Sent as `exclude` on every pagination call so the server doesn't
    // resurface a card already on screen this session. Deliberately a
    // recent window, not the full accumulated history: once `exhausted`
    // flips true and the server starts returning previously-seen cards
    // (allowRepeats), an ever-growing exclude list would also permanently
    // exclude every repeat candidate after one lap through the pool —
    // turning "endless scroll" into "ends after two laps instead of one."
    // Bounding it lets cards fall back out of exclusion and recirculate.
    private static let excludeWindow = 60
    private var recentExcludeIds: [String] { cards.suffix(Self.excludeWindow).map(\.id) }

    // Session-recap state — mirrors Feed.tsx's sessionViewsRef/
    // sessionCategories: purely client-side, scoped to this app launch
    // (never reset by a topic-filter reload, only by markViewed's own
    // per-card dedup resetting on a hard refresh — see apply(_:append:)).
    @Published private(set) var sessionViews = 0
    @Published private(set) var sessionTopicCount = 0
    private var viewedCardIds: Set<String> = []
    private var sessionCategories: Set<String> = []

    // Snapshotted once, the first time the daily card-count goal is crossed
    // this session — see markGoalReached(). nil means "not reached (yet)."
    private var goalReachedAfter: Int?

    // "Every other session" gating for the in-feed invite prompt — resolved
    // once per FeedViewModel lifetime (effectively once per app launch,
    // since FeedView only ever creates one), mirroring Feed.tsx's mount
    // effect over `sparklet.inviteSessionCount`.
    private var showInviteCard = false
    private static let inviteSessionCountKey = "sparklet.inviteSessionCount"

    // The topic filter — mirrors Feed.tsx's `selected` state, persisted via
    // CategoryPreference (its own `sparklet.categories` localStorage
    // equivalent). Empty means "Random / Everything."
    @Published private(set) var selectedCategorySlugs: [String]
    private let onboardingAPI = OnboardingAPI()

    init(authSession: AuthSession, purchaseManager: PurchaseManager) {
        self.authSession = authSession
        self.purchaseManager = purchaseManager
        self.selectedCategorySlugs = CategoryPreference.get()
        let defaults = UserDefaults.standard
        let n = defaults.integer(forKey: Self.inviteSessionCountKey) + 1
        defaults.set(n, forKey: Self.inviteSessionCountKey)
        showInviteCard = n % 2 == 0
    }

    func loadIfNeeded() async {
        guard cards.isEmpty else { return }
        await load()
    }

    // Mirrors Feed.tsx's applyCategories: persist the new filter, then a
    // full reset load (a topic change means "start over," not "append") —
    // matching the same reset semantics `load()` already documents below.
    // Also best-effort re-syncs POST /api/interests when the filter is
    // non-empty, so persisted interests (nudge targeting, new-user boost)
    // stay aligned with whatever the user actually filters to, not just
    // their original onboarding picks — same as the web.
    func applyCategoryFilter(_ slugs: [String]) async {
        selectedCategorySlugs = slugs
        CategoryPreference.set(slugs)
        await load()
        if !slugs.isEmpty {
            try? await onboardingAPI.submitInterests(categorySlugs: slugs, token: authSession.token)
        }
    }

    // Initial load and pull-to-refresh both replace the batch outright —
    // the feed is server-composed and stateless per request (sparklet/
    // src/lib/feed.ts), so "refresh" means "give me a fresh read," not
    // "append more." (An earlier pass appended here, which combined badly
    // with .refreshable on a paged scroll view: the visible card never
    // changed, so nothing looked refreshed, while excludeIds grew without
    // bound — see loadMoreIfNeeded below for where that trade is actually
    // made.)
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var response = try await api.fetchFeed(
                categorySlugs: selectedCategorySlugs, take: 10, token: authSession.token
            )
            if response.exhausted, Self.isEmpty(response) {
                // A returning account that's already seen every card and has
                // no due reviews — fall straight back to repeats rather than
                // opening on an empty feed.
                response = try await api.fetchFeed(
                    categorySlugs: selectedCategorySlugs, take: 10, allowRepeats: true, token: authSession.token
                )
            }
            apply(response, append: false)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            errorMessage = "Couldn't load the feed. Pull to retry."
        }
    }

    // Pagination: appends the next batch once the visible item nears the
    // end of what's loaded. Gated on position within `items`, not `cards` —
    // the visible item may be a quiz/guess/etc. sitting between cards, and
    // it still needs to trigger a load if it's near the tail of everything
    // loaded.
    func loadMoreIfNeeded(visibleItemId: String) async {
        guard !isLoading, let index = items.firstIndex(where: { $0.id == visibleItemId }) else { return }
        guard index >= items.count - 2 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var response = try await api.fetchFeed(
                categorySlugs: selectedCategorySlugs,
                take: 10,
                allowRepeats: exhausted,
                excludeIds: recentExcludeIds,
                token: authSession.token
            )
            if response.exhausted, Self.isEmpty(response), !exhausted {
                // Just crossed into "seen everything new" for the first time
                // this session — the call above already tried allowRepeats:
                // false. Retry once, immediately, with allowRepeats: true so
                // this single pagination trigger still makes forward
                // progress: visibleCardId only changes when the user scrolls
                // PAST the newly-loaded tail, which can never happen if
                // nothing new got appended — there'd be nothing to trigger a
                // second attempt.
                response = try await api.fetchFeed(
                    categorySlugs: selectedCategorySlugs,
                    take: 10,
                    allowRepeats: true,
                    excludeIds: recentExcludeIds,
                    token: authSession.token
                )
            }
            apply(response, append: true)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the user can still scroll what's already loaded.
        }
    }

    private static func isEmpty(_ response: FeedResponse) -> Bool {
        response.cards.isEmpty && response.quizzes.isEmpty && response.reviewQuizzes.isEmpty
            && response.guesses.isEmpty && response.misconceptions.isEmpty && response.explainPrompts.isEmpty
    }

    private func apply(_ response: FeedResponse, append: Bool) {
        if append {
            cards.append(contentsOf: response.cards)
            quizzes.append(contentsOf: response.quizzes)
            reviewQuizzes.append(contentsOf: response.reviewQuizzes)
            guesses.append(contentsOf: response.guesses)
            misconceptions.append(contentsOf: response.misconceptions)
            explainPrompts.append(contentsOf: response.explainPrompts)
        } else {
            cards = response.cards
            quizzes = response.quizzes
            reviewQuizzes = response.reviewQuizzes
            guesses = response.guesses
            misconceptions = response.misconceptions
            explainPrompts = response.explainPrompts
            // A hard reset (initial load or the refresh button) can bring
            // back a card already counted once — mirrors Feed.tsx's own
            // `if (opts?.reset) { viewedRef.current = new Set() }`. Session
            // totals themselves (sessionViews/sessionCategories) are NOT
            // reset here — they're scoped to the whole app launch, not to
            // any one fetched batch.
            viewedCardIds.removeAll()
        }
        exhausted = response.exhausted
        rebuildItems()
    }

    private func rebuildItems() {
        items = Self.buildItems(
            cards: cards,
            quizzes: quizzes,
            reviewQuizzes: reviewQuizzes,
            guesses: guesses,
            misconceptions: misconceptions,
            explainPrompts: explainPrompts,
            // Re-evaluated fresh on every rebuild (a fresh load/pagination),
            // not observed live — a user who subscribes mid-scroll stops
            // seeing new ad slides on their next load/refresh, not
            // retroactively mid-session. See AGENTS.md.
            premium: purchaseManager.premium,
            showInviteCard: showInviteCard,
            goalReachedAfter: goalReachedAfter
        )
    }

    private static let quizEvery = 10
    private static let guessEvery = 12
    private static let guessOffset = 1
    private static let misconceptionEvery = 10
    private static let misconceptionOffset = 2
    private static let explainEvery = 12
    private static let explainOffset = 3
    private static let adEvery = 6
    private static let checkinEvery = 15
    private static let inviteAfterCards = 12

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
        explainPrompts: [FeedExplainPrompt],
        premium: Bool = false,
        showInviteCard: Bool = false,
        goalReachedAfter: Int? = nil
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
            result.append(.card(card, occurrence: i))
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
            // Ports Feed.tsx's own comment verbatim: "never pushed at all
            // for premium users, not just hidden, so there's no dead ad
            // slide in a paying user's scroll."
            if !premium, position % adEvery == 0 {
                result.append(.ad(key: position))
            }
            // Check-in and invite both assume a signed-in account — this
            // client is always signed in by the time it can reach the feed
            // at all (see AGENTS.md's Invite section), so unlike Feed.tsx
            // there's no separate guest check to port here.
            if position % checkinEvery == 0 {
                result.append(.checkin(afterCount: position))
            }
            if showInviteCard, position == inviteAfterCards {
                result.append(.invite)
            }
            if let goalReachedAfter, position == goalReachedAfter {
                result.append(.goalReached)
            }
        }
        while reviewQuizCursor < reviewQuizzes.count {
            result.append(.reviewQuiz(reviewQuizzes[reviewQuizCursor]))
            reviewQuizCursor += 1
        }
        return result
    }

    // Mirrors Feed.tsx's markViewed: counts a card toward the session recap
    // (checkin/goalReached copy) the moment it's actually viewed —
    // unconditional of the 4.5s read-dwell gate trackView enforces below,
    // since "I scrolled past this" and "the server counted it as read" are
    // different questions. Keyed by cardId, not occurrence, so a
    // recirculated repeat of the same card (see FeedItem's occurrence
    // comment) doesn't inflate the count a second time within one batch.
    func markSessionView(cardId: String) {
        guard !viewedCardIds.contains(cardId) else { return }
        viewedCardIds.insert(cardId)
        sessionViews += 1
        addSessionCategory(cards.first { $0.id == cardId }?.category.name)
    }

    // Mirrors Feed.tsx's addSessionCategory — called both from
    // markSessionView (for a plain card) and from FeedView after a quiz/
    // guess/misconception/explain answer, since those count toward the
    // session's topic-count too even though they aren't cards.
    func addSessionCategory(_ name: String?) {
        guard let name else { return }
        sessionCategories.insert(name)
        sessionTopicCount = sessionCategories.count
    }

    // Snapshots the current sessionViews as the cards-array position the
    // goalReached slide should land at, the first time this session the
    // daily card-count goal is crossed — see buildItems' `position ==
    // goalReachedAfter` check. A no-op on any later call this session
    // (mirrors Feed.tsx's GOAL_HIT_KEY-gated markCardCompleted, which only
    // ever sets goalReachedAfter once).
    func markGoalReached() {
        guard goalReachedAfter == nil else { return }
        goalReachedAfter = sessionViews
        rebuildItems()
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
