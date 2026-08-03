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
    // Only used for the programmatic "Keep going"-style jumps below —
    // .scrollPosition(id:) alone is a well-known rough edge for exact
    // page-snapping when the id is set from code rather than a drag
    // gesture (see advanceToNextItem's comment); ScrollViewReader.scrollTo
    // is the more reliable API for that specific case.
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isRefreshing = false
    @State private var showingNotifications = false
    @State private var showingFriends = false
    @State private var showingOnboarding = false
    @State private var showingLeaderboard = false
    @State private var showingProfile = false
    @State private var showingStreakInfo = false
    @State private var showingXpInfo = false
    @State private var showingFeedSettings = false

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
        VStack(spacing: 0) {
            StatsHeaderView(
                profile: statsViewModel.profile,
                topicLabel: topicLabel,
                isRefreshing: isRefreshing,
                onRefresh: { Task { await refresh() } },
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.items) { item in
                            itemView(item)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .containerRelativeFrame(.vertical)
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden) // A vertical scrollbar implies a fixed
                // end the user can see coming — wrong signal for a feed
                // designed to keep loading indefinitely (see FeedViewModel's
                // allowRepeats-based pagination).
                .scrollContentBackground(.hidden)
                .scrollTargetBehavior(.paging)
                .defaultScrollAnchor(.top)
                .scrollPosition(id: $visibleCardId)
                .onAppear { scrollProxy = proxy }
            }
        }
        .background(Theme.background)
        .overlay {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView().tint(Theme.textTertiary)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            // .scrollPosition(id:) only reports changes after the initial
            // layout — it doesn't seed `visibleCardId` with whatever's
            // visible on first appearance. Without this, item 1 is never
            // tracked and the read-tracking .task below only starts firing
            // once the user scrolls to item 2.
            if visibleCardId == nil {
                visibleCardId = viewModel.items.first?.id
            }
            await statsViewModel.load()
            await notificationsViewModel.refreshUnreadCount()
            // Same one-time "first session, never onboarded" condition as
            // the web's feed-page redirect, computed server-side (see
            // ProfileResponse.needsOnboarding) — this client has no
            // server-driven page redirect to hook into, so a fullScreenCover
            // stands in for the web's separate /onboarding route.
            if statsViewModel.profile?.needsOnboarding == true {
                showingOnboarding = true
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
                    visibleCardId = viewModel.items.first?.id
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
            // position that's already on screen. That live insertion shifts
            // everything after it down by one page, and confirmed live: the
            // paging ScrollView doesn't reliably keep its offset aligned to
            // `visibleCardId` through that shift on its own, producing the
            // same half-settled/cut-off page glitch advanceToNextItem hit
            // (see its comment) — except here it happens automatically,
            // with no button tap involved. Re-snapping to the same id right
            // after the insertion forces the offset to match wherever that
            // id actually sits post-shift, instead of leaving the
            // pre-shift pixel offset in place.
            if let visibleCardId {
                scrollProxy?.scrollTo(visibleCardId, anchor: .top)
            }
        }
    }

    // "Keep going" / "Maybe later" on the checkin/invite/goalReached slides —
    // mirrors Feed.tsx's scrollNext (a raw pixel scrollBy); SwiftUI's
    // .scrollPosition(id:) binding needs the next item's id instead, found
    // via its position in the already-known `items` array.
    private func advanceToNextItem() {
        guard let visibleCardId,
              let index = viewModel.items.firstIndex(where: { $0.id == visibleCardId }),
              index + 1 < viewModel.items.count
        else { return }
        let nextId = viewModel.items[index + 1].id
        self.visibleCardId = nextId
    }

    // Mirrors the `inviteUrl` prop Feed.tsx receives from its server-rendered
    // parent page — this client has no such SSR step, so it's derived here
    // from the already-fetched profile id instead (same construction
    // ProfileView's own invite row uses).
    private var inviteURL: URL {
        AppConfig.apiBaseURL.appendingPathComponent("invite/\(statsViewModel.profile?.id ?? "")")
    }

    // An explicit button instead of `.refreshable`: this feed pages
    // vertically (`.scrollTargetBehavior(.paging)`), and simulator testing
    // on 2026-07-29 showed a deliberate pull-down at the true top of
    // content produces no rubber-band or refresh spinner at all — paging
    // fully consumes the overscroll gesture before SwiftUI's refresh
    // control ever sees it. Rather than fight that, this button gives the
    // same "give me a fresh read" action a guaranteed-reachable affordance.
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await viewModel.load()
        // `load()` replaces the batch outright, so the old id (if it even
        // still exists in the new batch) shouldn't carry over — reset to
        // the new first item, same as the initial-load seed above, so
        // tracking picks up on item 1 of the refreshed feed.
        visibleCardId = viewModel.items.first?.id
    }

    @ViewBuilder
    private func itemView(_ item: FeedItem) -> some View {
        switch item {
        case .card(let card, _):
            CardView(card: card, isVisible: item.id == visibleCardId)
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
