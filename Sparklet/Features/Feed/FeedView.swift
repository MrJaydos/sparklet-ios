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
    @StateObject private var viewModel: FeedViewModel
    @StateObject private var statsViewModel: StatsHeaderViewModel
    @StateObject private var notificationsViewModel: NotificationsViewModel
    @StateObject private var friendsViewModel: FriendsViewModel
    @StateObject private var onboardingViewModel: OnboardingViewModel
    @StateObject private var leaderboardViewModel: LeaderboardViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @State private var visibleCardId: String?
    @State private var isRefreshing = false
    @State private var showingNotifications = false
    @State private var showingFriends = false
    @State private var showingOnboarding = false
    @State private var showingLeaderboard = false
    @State private var showingProfile = false

    init(authSession: AuthSession) {
        _viewModel = StateObject(wrappedValue: FeedViewModel(authSession: authSession))
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
                isRefreshing: isRefreshing,
                onRefresh: { Task { await refresh() } },
                unreadNotifications: notificationsViewModel.unreadCount,
                onOpenNotifications: { showingNotifications = true },
                onOpenFriends: { showingFriends = true },
                onOpenLeaderboard: { showingLeaderboard = true },
                onOpenProfile: { showingProfile = true }
            )
            .padding(.vertical, 8)

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
            .scrollContentBackground(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleCardId)
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
            ProfileView(viewModel: profileViewModel)
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(viewModel: onboardingViewModel, onComplete: { showingOnboarding = false })
        }
        .task(id: visibleCardId) {
            // Only a `.card` item feeds the dwell-tracked read flow — a
            // quiz/guess/misconception/explain slot earns XP through its own
            // answer endpoint instead (see FeedItem.cardIdForReadTracking).
            guard let cardId = currentItem?.cardIdForReadTracking else { return }
            if let xp = await viewModel.trackView(cardId: cardId) {
                statsViewModel.apply(xp)
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
        case .card(let card):
            CardView(card: card)
        case .quiz(let quiz):
            QuizCardView(
                question: quiz.question,
                options: quiz.options,
                category: quiz.category,
                isReview: false,
                onSubmit: { index in await viewModel.answerQuiz(id: quiz.id, index: index) },
                onXp: { xp in statsViewModel.apply(xp, countsAsCard: false) }
            )
        case .reviewQuiz(let quiz):
            QuizCardView(
                question: quiz.question,
                options: quiz.options,
                category: quiz.category,
                isReview: true,
                onSubmit: { index in await viewModel.answerReview(id: quiz.id, index: index) },
                onXp: { xp in statsViewModel.apply(xp, countsAsCard: false) }
            )
        case .guess(let guess):
            GuessCardView(
                guess: guess,
                onSubmit: { value in await viewModel.answerGuess(id: guess.id, guess: value) },
                onXp: { xp in statsViewModel.apply(xp, countsAsCard: false) }
            )
        case .misconception(let misconception):
            MisconceptionCardView(
                misconception: misconception,
                onSubmit: { choice in await viewModel.answerMisconception(id: misconception.id, guess: choice) },
                onXp: { xp in statsViewModel.apply(xp, countsAsCard: false) }
            )
        case .explain(let prompt):
            ExplainCardView(
                prompt: prompt,
                onSubmit: { text in await viewModel.answerExplain(cardId: prompt.id, text: text) },
                onSkip: { await viewModel.skipExplain(cardId: prompt.id) },
                onXp: { xp in statsViewModel.apply(xp, countsAsCard: false) }
            )
        }
    }
}
