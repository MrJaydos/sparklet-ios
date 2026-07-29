import Foundation

// Mirrors POST /api/invite/[refId]/accept (sparklet/src/app/api/invite/
// [refId]/accept/route.ts).
struct InviteAPI {
    let client: APIClient = .shared

    private struct EmptyBody: Encodable {}

    func accept(refId: String, token: String?) async throws -> InviteResponse {
        try await client.post("api/invite/\(refId)/accept", body: EmptyBody(), token: token)
    }
}
