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
