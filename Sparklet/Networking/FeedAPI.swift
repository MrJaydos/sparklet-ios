import Foundation

// Mirrors POST /api/interactions's body (sparklet/src/app/api/interactions/route.ts).
struct InteractionRequest: Encodable {
    let cardId: String
    let action = "view"
    let tzOffsetMinutes: Int
    let dwellMs: Int?
}

struct FeedAPI {
    let client: APIClient = .shared

    func fetchFeed(
        categorySlugs: [String] = [],
        take: Int = 10,
        allowRepeats: Bool = false,
        excludeIds: [String] = [],
        token: String?
    ) async throws -> FeedResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "take", value: String(take))]
        if !categorySlugs.isEmpty {
            query.append(URLQueryItem(name: "categories", value: categorySlugs.joined(separator: ",")))
        }
        if allowRepeats {
            query.append(URLQueryItem(name: "allowRepeats", value: "1"))
        }
        if !excludeIds.isEmpty {
            query.append(URLQueryItem(name: "exclude", value: excludeIds.joined(separator: ",")))
        }
        return try await client.get("api/feed", query: query, token: token)
    }

    // `dwellMs` is sent for the server's own bookkeeping, but never trusted
    // as proof of a read — the backend gates "completed" on the gap between
    // this call and a prior /api/interactions POST for the same card,
    // measured by its own clock (MIN_READ_GAP_MS in interactions/route.ts).
    // Callers must issue the entry-view POST first, wait for the real dwell,
    // then send this one — there is no client-side shortcut.
    func postInteraction(
        cardId: String,
        dwellMs: Int? = nil,
        token: String?
    ) async throws -> InteractionResponse {
        // Deliberately negated: the backend's tzOffsetMinutes convention is
        // JS's Date.getTimezoneOffset() (minutes WEST of UTC, e.g. EST=+300),
        // the opposite sign from Swift's secondsFromGMT() (positive EAST).
        // Don't "fix" this to match Swift's native sign — it needs to match
        // localDayStart in sparklet/src/lib/xp.ts.
        let tzOffsetMinutes = TimeZone.current.secondsFromGMT() / -60
        let body = InteractionRequest(cardId: cardId, tzOffsetMinutes: tzOffsetMinutes, dwellMs: dwellMs)
        return try await client.post("api/interactions", body: body, token: token)
    }
}
