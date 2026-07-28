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
}
