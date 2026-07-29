import Foundation

// Mirrors GET /api/profile/details (sparklet/src/app/api/profile/details/
// route.ts) — everything the web profile page shows beyond the lightweight
// xp/streak numbers already in ProfileResponse: badges, history, notebook
// (saved cards), top categories, and due-reviews count. Friends/friendCode
// are deliberately not duplicated here — see FriendsResponse.
struct ProfileDetailsResponse: Decodable {
    let id: String
    let name: String
    let email: String
    let xp: Int
    let currentStreak: Int
    let longestStreak: Int
    let freezesAvailable: Int
    let totalViewed: Int
    let dueReviews: Int
    let badges: [Badge]
    let topCategories: [TopCategory]
    let savedCards: [SavedCard]
    let history: [HistoryEntry]
}

struct Badge: Decodable, Identifiable, Hashable {
    let key: String
    let icon: String
    let name: String
    let value: Int
    let earnedTier: BadgeTier?
    let nextTier: BadgeTier?

    var id: String { key }
}

struct BadgeTier: Decodable, Hashable {
    let threshold: Int
    let label: String
}

struct TopCategory: Decodable, Hashable {
    let name: String
    let icon: String
    let colorHex: String
    let count: Int
}

struct SavedCard: Decodable, Identifiable, Hashable {
    let cardId: String
    let title: String
    let icon: String
    let colorHex: String

    var id: String { cardId }
}

// Not Identifiable: history can legitimately repeat a card (re-read after a
// spaced repetition review), so cardId alone isn't a stable unique id —
// callers should key ForEach by array offset instead.
struct HistoryEntry: Decodable, Hashable {
    let cardId: String
    let title: String
    let icon: String
    let colorHex: String
    let when: String
}
