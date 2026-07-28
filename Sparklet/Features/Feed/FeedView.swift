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
    @State private var visibleCardId: String?

    init(authSession: AuthSession) {
        _viewModel = StateObject(wrappedValue: FeedViewModel(authSession: authSession))
        _statsViewModel = StateObject(wrappedValue: StatsHeaderViewModel(authSession: authSession))
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsHeaderView(profile: statsViewModel.profile)
                .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.cards) { card in
                        CardView(card: card)
                            .containerRelativeFrame(.vertical)
                            .id(card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleCardId)
        }
        .overlay {
            if viewModel.isLoading && viewModel.cards.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.load()
            // `load()` replaces the batch outright, so the old id (if it
            // even still exists in the new batch) shouldn't carry over —
            // reset to the new first card, same as the initial-load seed
            // below, so tracking picks up on card 1 of the refreshed feed.
            visibleCardId = viewModel.cards.first?.id
        }
        .task {
            await viewModel.loadIfNeeded()
            // .scrollPosition(id:) only reports changes after the initial
            // layout — it doesn't seed `visibleCardId` with whatever's
            // visible on first appearance. Without this, card 1 is never
            // tracked and the read-tracking .task below only starts firing
            // once the user scrolls to card 2.
            if visibleCardId == nil {
                visibleCardId = viewModel.cards.first?.id
            }
            await statsViewModel.load()
        }
        .task(id: visibleCardId) {
            guard let visibleCardId else { return }
            if let xp = await viewModel.trackView(cardId: visibleCardId) {
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
            await viewModel.loadMoreIfNeeded(currentId: visibleCardId)
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
}
