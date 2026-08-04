import SwiftUI

// Paged, one-card-at-a-time scroll: `visibleCardId` tracks whichever card is
// actually centered on screen, and a single `.task(id:)` at the container
// level runs the read-tracking flow for that card only. This is not
// cosmetic — a naive per-card `.task` inside the LazyVStack fires for every
// instantiated card (the 2-3 on screen plus SwiftUI's prefetch buffer)
// concurrently, and the backend's 4.5s server-clock gate (see
// FeedViewModel.trackView) can't tell that apart from a real read: the gap
// genuinely elapses even if the user never looked at those cards. Only
// tracking the single visible card keeps the client honest about what it's
// claiming, not just about what dwellMs it sends.
struct FeedView: View {
    let authSession: AuthSession
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @StateObject private var viewModel: FeedViewModel
    @StateObject private var statsViewModel: StatsHeaderViewModel
    @StateObject private var notificationsViewModel: NotificationsViewModel
    @StateObject private var friendsViewModel: FriendsViewModel
    @StateObject private var onboardingViewModel: OnboardingViewModel
    @StateObject private var leaderboardViewModel: LeaderboardViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @State private var visibleCardId: String?
    // Set once by FeedPagingView's makeUIView — the handle for every
    // programmatic jump below (advanceToNextItem, the goal-reached
    // re-snap, and the load()/refresh()/filter-apply/reconcile reseeds).
    @State private var pagingProxy: FeedPagingProxy?
    @State private var isRefreshing = false
    @State private var showingNotifications = false
    @State private var showingFriends = false
    @State private var showingOnboarding = false
    @State private var showingLeaderboard = false
    @State private var showingProfile = false
    @State private var showingStreakInfo = false
    @State private var showingXpInfo = false
    @State private var showingFeedSettings = false
    // Mirrors Feed.tsx's one-time swipe hint — "sparklet.hinted" is the same
    // key name the web uses for its own localStorage entry (not shared
    // storage, just parity, same precedent as DepthPreference/
    // CategoryPreference).
    @AppStorage("sparklet.hinted") private var hasSeenSwipeHint = false
    @State private var showSwipeHint = false

    init(authSession: AuthSession, purchaseManager: PurchaseManager) {
        self.authSession = authSession
        _viewModel = StateObject(wrappedValue: FeedViewModel(authSession: authSession, purchaseManager: purchaseManager))
        _statsViewModel = StateObject(wrappedValue: StatsHeaderViewModel(authSession: authSession))
        _notificationsViewModel = StateObject(wrappedValue: NotificationsViewModel(authSession: authSession))
        _friendsViewModel = StateObject(wrappedValue: FriendsViewModel(authSession: authSession))
        _onboardingViewModel = StateObject(wrappedValue: OnboardingViewModel(authSession: authSession))
        _leaderboardViewModel = StateObject(wrappedValue: LeaderboardViewModel(authSession: authSession))
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(authSession: authSession))
    }

    var body: some View {
        ZStack {
            // A single full-screen backdrop, driven by whichever item is
            // currently visible, sitting behind BOTH the scroll content and
            // the header — mirrors AppHeader.tsx, which floats
            // (`fixed inset-x-0 top-0`) with no background of its own over
            // whichever card/quiz/guess/etc.'s own gradient is showing
            // through underneath, rather than the header sitting on a flat
            // opaque bar. Previously each slide painted its own gradient
            // scoped to its own frame (below the header), so the wash never
            // reached the area behind the header/status bar at all.
            feedBackdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StatsHeaderView(
                    profile: statsViewModel.profile,
                    topicLabel: topicLabel,
                    hasCategoryFilter: !viewModel.selectedCategorySlugs.isEmpty,
                    unreadNotifications: notificationsViewModel.unreadCount,
                    onOpenNotifications: { showingNotifications = true },
                    onOpenFriends: { showingFriends = true },
                    onOpenLeaderboard: { showingLeaderboard = true },
                    onOpenProfile: { showingProfile = true },
                    onOpenStreakInfo: { showingStreakInfo = true },
                    onOpenXpInfo: { showingXpInfo = true },
                    onOpenFeedSettings: { showingFeedSettings = true }
                )
                .padding(.vertical, 8)

                // UIKit-backed paging (see FeedPagingView.swift's own
                // comment for the full history) — replaces a SwiftUI
                // ScrollView + LazyVStack + .scrollTargetBehavior(.paging)
                // that let each item's computed height drift out of
                // agreement with the actual per-swipe scroll distance,
                // which produced two live-confirmed bugs (a sliver of the
                // next item peeking at the bottom of every page, and a
                // worse regression where the PREVIOUS item's content bled
                // into the top of the screen on some pages).
                FeedPagingView(
                    items: viewModel.items,
                    visibleCardId: $visibleCardId,
                    onProxyReady: { pagingProxy = $0 },
                    onRefresh: { await refresh() }
                ) { item, isVisible in
                    // Cards and every interactive slide kind that carries a
                    // category (quiz/guess/misconception/explain) go
                    // edge-to-edge — LearnCard.tsx/QuizView.tsx/
                    // GuessView.tsx/MisconceptionView.tsx/ExplainView.tsx
                    // are all the same `h-dvh w-full` full-bleed shape on
                    // the web, none of them a boxed panel. Ad/checkin/
                    // invite/goalReached (no per-category color to show)
                    // keep the boxed panel treatment they already had.
                    if isEdgeToEdge(item) {
                        itemView(item, isVisible: isVisible)
                    } else {
                        itemView(item, isVisible: isVisible)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView().tint(Theme.textTertiary)
            }
        }
        .overlay(alignment: .bottom) {
            if showSwipeHint {
                SwipeHintOverlayView()
                    .padding(.bottom, 48)
            }
        }
        // Mirrors Feed.tsx's onScroll={showSwipeHint ? dismissSwipeHint :
        // undefined} — dismissed by the first real swipe. visibleCardId
        // only changes once a swipe actually settles on a different item,
        // not on every scroll pixel like the web's onScroll, but it's the
        // closest signal this paging ScrollView exposes for "the user swiped."
        .onChange(of: visibleCardId) { _, _ in
            if showSwipeHint {
                showSwipeHint = false
                hasSeenSwipeHint = true
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            // A freshly created UICollectionView starts at contentOffset
            // zero (index 0) on its own, so this just needs to seed the
            // SwiftUI-side state to match — no scroll command needed for
            // this first-appearance case. Without this, item 1 is never
            // tracked and the read-tracking .task below only starts firing
            // once the user scrolls to item 2.
            if visibleCardId == nil {
                visibleCardId = viewModel.items.first?.id
            }
            await statsViewModel.load()
            await notificationsViewModel.refreshUnreadCount()
            // Mirrors Feed.tsx's mount effect: the local CategoryPreference
            // paints instantly above via loadIfNeeded(), but the server's
            // UserInterest rows are the durable cross-device source of
            // truth — reconcile after that first paint, and re-seed
            // visibleCardId if the reconcile ends up replacing the batch.
            await viewModel.reconcileCategoryFilterWithServer()
            if let firstId = viewModel.items.first?.id, visibleCardId != firstId {
                pagingProxy?.scrollTo(firstId, false)
            }
            // Same one-time "first session, never onboarded" condition as
            // the web's feed-page redirect, computed server-side (see
            // ProfileResponse.needsOnboarding) — this client has no
            // server-driven page redirect to hook into, so a fullScreenCover
            // stands in for the web's separate /onboarding route.
            if statsViewModel.profile?.needsOnboarding == true {
                showingOnboarding = true
            }
            // Mirrors Feed.tsx's one-time swipe hint — gated on
            // items.count > 1 (cards.length > 1 on the web) so it never
            // shows over a single-item feed with nothing to swipe to.
            // Activated last, after every internal visibleCardId reseed
            // above, so the .onChange(of: visibleCardId) dismissal handler
            // only ever fires on a genuine user swipe, not one of those
            // programmatic reseeds.
            if !hasSeenSwipeHint && viewModel.items.count > 1 {
                showSwipeHint = true
            }
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationsView(viewModel: notificationsViewModel)
        }
        .sheet(isPresented: $showingFriends) {
            FriendsView(viewModel: friendsViewModel)
        }
        .sheet(isPresented: $showingLeaderboard) {
            LeaderboardView(viewModel: leaderboardViewModel)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView(viewModel: profileViewModel, authSession: authSession)
        }
        .sheet(isPresented: $showingFeedSettings) {
            FeedSettingsView(
                authSession: authSession,
                purchaseManager: purchaseManager,
                selected: viewModel.selectedCategorySlugs,
                onApply: { slugs in
                    await viewModel.applyCategoryFilter(slugs)
                    // A filter change replaces the batch outright (same
                    // "reset means reset" semantics as refresh() below) —
                    // reseed so read-tracking picks up on the new item 1.
                    if let firstId = viewModel.items.first?.id {
                        pagingProxy?.scrollTo(firstId, false)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(viewModel: onboardingViewModel, onComplete: { showingOnboarding = false })
        }
        .topDropdown(isPresented: $showingStreakInfo) {
            if let profile = statsViewModel.profile {
                StreakInfoView(
                    streak: profile.currentStreak,
                    longestStreak: profile.longestStreak,
                    freezesAvailable: profile.freezesAvailable,
                    onClose: { showingStreakInfo = false }
                )
            }
        }
        .topDropdown(isPresented: $showingXpInfo) {
            if let profile = statsViewModel.profile {
                XpInfoView(
                    today: profile.xpToday,
                    goal: profile.xpGoal,
                    onClose: { showingXpInfo = false }
                )
            }
        }
        .task(id: visibleCardId) {
            // Only a `.card` item feeds the dwell-tracked read flow — a
            // quiz/guess/misconception/explain slot earns XP through its own
            // answer endpoint instead (see FeedItem.cardIdForReadTracking).
            guard let cardId = currentItem?.cardIdForReadTracking else { return }
            // Unconditional of the read-dwell gate below — mirrors Feed.tsx's
            // markViewed, which counts a card toward the session recap the
            // moment it's scrolled to, not once the server has counted a read.
            viewModel.markSessionView(cardId: cardId)
            if let xp = await viewModel.trackView(cardId: cardId) {
                applyXpAndCheckGoal(xp)
            }
        }
        // Deliberately a separate .task from the one above: trackView
        // sleeps ~4.7s before its second POST, so pagination sitting behind
        // it in the same task would never run on a swipe faster than that —
        // exactly the core interaction of a swipe feed. Both fire
        // independently on the same visibleCardId change.
        .task(id: visibleCardId) {
            guard let visibleCardId else { return }
            await viewModel.loadMoreIfNeeded(visibleItemId: visibleCardId)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var currentItem: FeedItem? {
        guard let visibleCardId else { return nil }
        return viewModel.items.first { $0.id == visibleCardId }
    }

    // Mirrors LearnCard.tsx/QuizView.tsx/GuessView.tsx/MisconceptionView.tsx/
    // ExplainView.tsx's shared backdrop:
    // `linear-gradient(160deg, ${colorHex}26 0%, #0a0a0a 45%, #0a0a0a 100%)`.
    // Computed once here at the feed level (not per-item) since only one
    // item is ever visible at a time in this paging feed — a single global
    // layer behind the header achieves the exact same look as painting it
    // per-item, but also reaches behind the header, which a per-item
    // background scoped to that item's own frame never could.
    private var feedBackdrop: some View {
        Group {
            if let hex = currentCategoryColorHex {
                LinearGradient(
                    stops: [
                        .init(color: Color(hexString: hex).opacity(0.15), location: 0),
                        .init(color: Theme.background, location: 0.45),
                        .init(color: Theme.background, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Theme.background
            }
        }
    }

    private var currentCategoryColorHex: String? {
        guard let currentItem else { return nil }
        switch currentItem {
        case .card(let c, _): return c.category.colorHex
        case .quiz(let q): return q.category.colorHex
        case .reviewQuiz(let q): return q.category.colorHex
        case .guess(let g): return g.category.colorHex
        case .misconception(let m): return m.category.colorHex
        case .explain(let e): return e.category.colorHex
        // Ads get their own fixed "sponsored" gold tint rather than no
        // color at all — matches AdSlideView's own chip color, and reads
        // more like a deliberate brand choice than a blank page.
        case .ad: return "#fbbf24"
        case .checkin, .invite, .goalReached: return nil
        }
    }

    private func isEdgeToEdge(_ item: FeedItem) -> Bool {
        switch item {
        // Ads now use the same full-bleed card shape as every real card —
        // flagged live by the user as looking out of place boxed while
        // everything else went edge-to-edge (see AdSlideView's own comment
        // for the full redesign).
        case .card, .quiz, .reviewQuiz, .guess, .misconception, .explain, .ad: return true
        case .checkin, .invite, .goalReached: return false
        }
    }

    // Mirrors Feed.tsx's topicLabel — simplified to a count rather than the
    // web's space-joined category icons, since showing icons here would mean
    // this view also holding its own copy of the categories list just for
    // that, on top of the one FeedSettingsView already fetches when opened.
    private var topicLabel: String {
        let count = viewModel.selectedCategorySlugs.count
        return count == 0 ? "🎲" : "\(count)"
    }

    // Shared by every XP-awarding path (read-tracking above, and each
    // quiz/guess/misconception/explain onXp closure below) — updates the
    // header, then checks whether this specific update just crossed the
    // daily card-count goal, triggering the one-per-day goalReached slide.
    // Mirrors Feed.tsx's handleXp + the crossing check inside
    // markCardCompleted, which every answer handler calls unconditionally
    // too (see StatsHeaderViewModel.apply's comment on why quiz/guess/
    // misconception/explain answers count toward this goal same as reads).
    private func applyXpAndCheckGoal(_ xp: XpSummary) {
        if statsViewModel.apply(xp), DailyCardGoal.markReachedIfNeededToday() {
            viewModel.markGoalReached()
            // markGoalReached() inserts a new .goalReached item into
            // `items`, and it always lands at/right after whatever card the
            // user is currently on (goalReachedAfter is a snapshot of
            // sessionViews taken at this exact moment) — i.e. exactly the
            // position that's already on screen. FeedPagingView's diffable
            // data source preserves scroll position through an insertion
            // like this on its own (unlike the old SwiftUI ScrollView,
            // which needed this explicit re-snap to fix a half-settled/
            // cut-off page glitch after exactly this kind of live mid-feed
            // insertion) — this call is now a defensive no-op-if-already-
            // there safety net, kept in case that guarantee doesn't hold in
            // some edge case, not a required fix.
            if let visibleCardId {
                pagingProxy?.scrollTo(visibleCardId, true)
            }
        }
    }

    // "Keep going" / "Maybe later" on the checkin/invite/goalReached slides —
    // mirrors Feed.tsx's scrollNext (a raw pixel scrollBy); finds the next
    // item's id via its position in the already-known `items` array, then
    // hands it to FeedPagingView to actually scroll there.
    private func advanceToNextItem() {
        guard let visibleCardId,
              let index = viewModel.items.firstIndex(where: { $0.id == visibleCardId }),
              index + 1 < viewModel.items.count
        else { return }
        pagingProxy?.scrollTo(viewModel.items[index + 1].id, true)
    }

    // Mirrors the `inviteUrl` prop Feed.tsx receives from its server-rendered
    // parent page — this client has no such SSR step, so it's derived here
    // from the already-fetched profile id instead (same construction
    // ProfileView's own invite row uses).
    private var inviteURL: URL {
        AppConfig.apiBaseURL.appendingPathComponent("invite/\(statsViewModel.profile?.id ?? "")")
    }

    // Previously an explicit header button rather than real pull-to-refresh:
    // the SwiftUI ScrollView + .scrollTargetBehavior(.paging) this feed used
    // to page with consumed the overscroll gesture before SwiftUI's own
    // refresh control ever saw it (confirmed live 2026-07-29). Once the feed
    // moved to a UIKit UICollectionView (see FeedPagingView.swift),
    // UIRefreshControl's pull gesture had no such conflict to begin with —
    // isPagingEnabled only affects snap behavior once a drag ends, not the
    // overscroll drag itself — so real pull-to-refresh is wired there
    // instead, and the header button (requested removed in favor of it) is
    // gone.
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await viewModel.load()
        // `load()` replaces the batch outright, so the old id (if it even
        // still exists in the new batch) shouldn't carry over — reset to
        // the new first item, same as the initial-load seed above, so
        // tracking picks up on item 1 of the refreshed feed.
        if let firstId = viewModel.items.first?.id {
            pagingProxy?.scrollTo(firstId, false)
        }
    }

    @ViewBuilder
    private func itemView(_ item: FeedItem, isVisible: Bool) -> some View {
        switch item {
        case .card(let card, _):
            CardView(card: card, isVisible: isVisible)
        case .quiz(let quiz):
            QuizCardView(
                question: quiz.question,
                options: quiz.options,
                category: quiz.category,
                isReview: false,
                onSubmit: { index in await viewModel.answerQuiz(id: quiz.id, index: index) },
                onXp: { xp in
                    viewModel.addSessionCategory(quiz.category.name)
                    applyXpAndCheckGoal(xp)
                }
            )
        case .reviewQuiz(let quiz):
            QuizCardView(
                question: quiz.question,
                options: quiz.options,
                category: quiz.category,
                isReview: true,
                onSubmit: { index in await viewModel.answerReview(id: quiz.id, index: index) },
                onXp: { xp in
                    viewModel.addSessionCategory(quiz.category.name)
                    applyXpAndCheckGoal(xp)
                }
            )
        case .guess(let guess):
            GuessCardView(
                guess: guess,
                onSubmit: { value in await viewModel.answerGuess(id: guess.id, guess: value) },
                onXp: { xp in
                    viewModel.addSessionCategory(guess.category.name)
                    applyXpAndCheckGoal(xp)
                }
            )
        case .misconception(let misconception):
            MisconceptionCardView(
                misconception: misconception,
                onSubmit: { choice in await viewModel.answerMisconception(id: misconception.id, guess: choice) },
                onXp: { xp in
                    viewModel.addSessionCategory(misconception.category.name)
                    applyXpAndCheckGoal(xp)
                }
            )
        case .explain(let prompt):
            ExplainCardView(
                prompt: prompt,
                onSubmit: { text in await viewModel.answerExplain(cardId: prompt.id, text: text) },
                onSkip: { await viewModel.skipExplain(cardId: prompt.id) },
                onXp: { xp in
                    viewModel.addSessionCategory(prompt.category.name)
                    applyXpAndCheckGoal(xp)
                }
            )
        case .ad:
            AdSlideView()
        case .checkin:
            CheckinSlideView(
                sessionViews: viewModel.sessionViews,
                topicCount: viewModel.sessionTopicCount,
                inviteUrl: inviteURL,
                onContinue: advanceToNextItem
            )
        case .invite:
            InviteSlideView(inviteUrl: inviteURL, onContinue: advanceToNextItem)
        case .goalReached:
            GoalReachedSlideView(
                cardsToday: statsViewModel.profile?.cardsToday ?? 0,
                dailyGoal: DailyCardGoal.current,
                sessionViews: viewModel.sessionViews,
                topicCount: viewModel.sessionTopicCount,
                onContinue: advanceToNextItem,
                onDone: { showingProfile = true }
            )
        }
    }
}
