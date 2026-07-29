import Foundation

struct ProfileAPI {
    let client: APIClient = .shared

    // `tz`: the route falls back to the `sparklet.tz` cookie (a web-only
    // convention), so native clients must always pass this explicitly —
    // see the route's own comment in sparklet/src/app/api/profile/route.ts.
    func fetchProfile(token: String?) async throws -> ProfileResponse {
        // Same sign convention as FeedAPI's InteractionRequest — JS-west-
        // positive, not Swift-native. See the comment there.
        let tzOffsetMinutes = TimeZone.current.secondsFromGMT() / -60
        return try await client.get(
            "api/profile",
            query: [URLQueryItem(name: "tz", value: String(tzOffsetMinutes))],
            token: token
        )
    }

    // Separate route from GET /api/profile — that one is polled on every
    // feed load, this data (badges/history/notebook/top categories) is only
    // needed when the Profile screen itself opens. See the route's own
    // comment (sparklet/src/app/api/profile/details/route.ts).
    func fetchDetails(token: String?) async throws -> ProfileDetailsResponse {
        try await client.get("api/profile/details", token: token)
    }

    private struct UpdateNameRequest: Encodable { let name: String }
    private struct UpdateNameResponse: Decodable { let ok: Bool; let name: String? }

    func updateName(_ name: String, token: String?) async throws {
        let _: UpdateNameResponse = try await client.patch(
            "api/profile",
            body: UpdateNameRequest(name: name),
            token: token
        )
    }
}
