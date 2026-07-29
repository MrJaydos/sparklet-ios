import Foundation

@MainActor
final class StatsHeaderViewModel: ObservableObject {
    @Published private(set) var profile: ProfileResponse?

    private let api = ProfileAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func load() async {
        do {
            profile = try await api.fetchProfile(token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort: the feed itself still works without the header.
        }
    }

    // Updates the header from a read POST's own response instead of
    // re-fetching /api/profile after every card — InteractionResponse.xp
    // already carries today's/lifetime totals and the streak delta.
    // `cardsToday` isn't in XpSummary, but the backend's own invariant
    // (one XpEvent row per positive award — see xp.ts) means it advances
    // exactly when `awarded > 0` does, so it's derived rather than stale
    // until the next full load.
    //
    // `countsAsCard` must be false for quiz/guess/misconception/explain
    // answers — those award XP too, but answering one isn't "reading a
    // card," and the daily card-count goal and the XP ring are deliberately
    // separate questions (see AGENTS.md). Only the read-tracking flow in
    // FeedViewModel.trackView should pass true.
    func apply(_ xp: XpSummary, countsAsCard: Bool = true) {
        guard let current = profile else { return }
        // On the no-award path (already-completed card, rate-limited read),
        // interactions/route.ts hardcodes `total: 0` rather than the real
        // lifetime sum — only `today`/`goal` are meaningful there. Falling
        // back to the last known `xp` avoids clobbering it to zero.
        profile = ProfileResponse(
            id: current.id,
            xp: xp.awarded > 0 ? xp.total : current.xp,
            xpToday: xp.today,
            xpGoal: xp.goal,
            cardsToday: current.cardsToday + (countsAsCard && xp.awarded > 0 ? 1 : 0),
            currentStreak: xp.streak?.currentStreak ?? current.currentStreak,
            longestStreak: xp.streak?.longestStreak ?? current.longestStreak,
            freezesAvailable: xp.streak?.freezesAvailable ?? current.freezesAvailable,
            needsOnboarding: current.needsOnboarding
        )
    }
}
