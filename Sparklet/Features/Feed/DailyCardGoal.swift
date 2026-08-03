import Foundation

// Mirrors CategorySheet.tsx's `sparklet.dailyGoal`/DEFAULT_DAILY_CARD_GOAL
// and Feed.tsx's `sparklet.goalHit` — the daily "things learned" count goal,
// distinct from the fixed XP ring goal (see AGENTS.md). Adjustable via
// FeedSettingsView, same [5, 10, 15, 20, 30] options the web offers.
enum DailyCardGoal {
    private static let goalKey = "sparklet.dailyGoal"
    private static let goalHitKey = "sparklet.goalHit"
    static let defaultGoal = 10
    static let options = [5, 10, 15, 20, 30]

    static var current: Int {
        let stored = UserDefaults.standard.integer(forKey: goalKey)
        return stored > 0 ? stored : defaultGoal
    }

    static func set(_ goal: Int) {
        UserDefaults.standard.set(goal, forKey: goalKey)
    }

    // Mirrors the web's date-string guard: the goal-reached celebration
    // fires at most once per local calendar day, even if this is called
    // again later the same day (e.g. a second crossing-edge false-positive,
    // or the app relaunching after the goal was already hit earlier today).
    // Returns true only the first time it's called on a given day.
    @discardableResult
    static func markReachedIfNeededToday() -> Bool {
        let today = todayString()
        guard UserDefaults.standard.string(forKey: goalHitKey) != today else { return false }
        UserDefaults.standard.set(today, forKey: goalHitKey)
        return true
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
