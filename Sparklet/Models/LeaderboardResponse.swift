import Foundation

// Mirrors GET /api/leaderboard (sparklet/src/app/api/leaderboard/route.ts),
// which ports the ranking logic straight out of the web's
// src/app/leaderboard/page.tsx — that page had no API route backing it.
struct LeaderboardResponse: Decodable {
    let board: String
    let rows: [LeaderboardRow]
    let me: LeaderboardSelf?
    let inTop: Bool
    let selfName: String
    let viewerId: String
}

struct LeaderboardRow: Decodable, Identifiable, Hashable {
    let userId: String
    let name: String
    let xp: Int

    var id: String { userId }
}

struct LeaderboardSelf: Decodable, Hashable {
    let xp: Int
    let rank: Int
}
