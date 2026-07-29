import Foundation

// Mirrors GET /api/leaderboard (sparklet/src/app/api/leaderboard/route.ts).
struct LeaderboardAPI {
    let client: APIClient = .shared

    func fetch(board: String, token: String?) async throws -> LeaderboardResponse {
        // Same tz query-param convention as ProfileAPI — see the comment there.
        let tzOffsetMinutes = TimeZone.current.secondsFromGMT() / -60
        return try await client.get(
            "api/leaderboard",
            query: [
                URLQueryItem(name: "board", value: board),
                URLQueryItem(name: "tz", value: String(tzOffsetMinutes)),
            ],
            token: token
        )
    }
}
