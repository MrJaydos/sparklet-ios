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
    // exactly when `awarded > 0` does, regardless of whether the award came
    // from a card read, review recall, quiz, guess, or misconception check —
    // getCardsToday (sparklet/src/lib/xp.ts) counts ALL of those the same
    // way ("Any new XP-awarding action implicitly becomes one more 'card'
    // toward that goal"). An earlier pass here had a `countsAsCard` flag
    // that excluded quiz/guess/misconception/explain answers from bumping
    // cardsToday — that was a misreading of the backend's actual semantics,
    // not an intentional distinction; removed rather than kept as dead
    // config, since every caller needed it true anyway.
    //
    // Returns whether this call just crossed the daily card-count goal
    // (previous < goal, new >= goal) — mirrors Feed.tsx's markCardCompleted
    // edge check — so callers can trigger the goalReached feed slide.
    @discardableResult
    func apply(_ xp: XpSummary) -> Bool {
        guard let current = profile else { return false }
        let previousCardsToday = current.cardsToday
        let nextCardsToday = previousCardsToday + (xp.awarded > 0 ? 1 : 0)
        // On the no-award path (already-completed card, rate-limited read),
        // interactions/route.ts hardcodes `total: 0` rather than the real
        // lifetime sum — only `today`/`goal` are meaningful there. Falling
        // back to the last known `xp` avoids clobbering it to zero.
        profile = ProfileResponse(
            id: current.id,
            xp: xp.awarded > 0 ? xp.total : current.xp,
            xpToday: xp.today,
            xpGoal: xp.goal,
            cardsToday: nextCardsToday,
            currentStreak: xp.streak?.currentStreak ?? current.currentStreak,
            longestStreak: xp.streak?.longestStreak ?? current.longestStreak,
            freezesAvailable: xp.streak?.freezesAvailable ?? current.freezesAvailable,
            needsOnboarding: current.needsOnboarding
        )
        let goal = DailyCardGoal.current
        return previousCardsToday < goal && nextCardsToday >= goal
    }
}
