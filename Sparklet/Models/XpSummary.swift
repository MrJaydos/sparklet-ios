import Foundation

// Mirrors StreakSummary embedded in XpSummary (sparklet/src/lib/xp.ts).
struct StreakSummary: Codable, Hashable {
    let currentStreak: Int
    let longestStreak: Int
    let freezesUsed: Int
    let freezesAvailable: Int
}

// Mirrors XpSummary (sparklet/src/lib/xp.ts). `streak` is present only on
// the action that pushes today's completions past STREAK_MIN_CARDS.
struct XpSummary: Codable, Hashable {
    let awarded: Int
    let today: Int
    let total: Int
    let goal: Int
    let streak: StreakSummary?
}

// Mirrors the POST /api/interactions response body
// (sparklet/src/app/api/interactions/route.ts).
struct InteractionResponse: Codable {
    let ok: Bool
    let streak: StreakSummary?
    let xp: XpSummary
    let read: Bool
}
