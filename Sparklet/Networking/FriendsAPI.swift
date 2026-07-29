import Foundation

// Mirrors GET/POST /api/friends and PATCH/DELETE /api/friends/[id]
// (sparklet/src/app/api/friends/route.ts, .../[id]/route.ts).
struct FriendsAPI {
    let client: APIClient = .shared

    func fetch(token: String?) async throws -> FriendsResponse {
        try await client.get("api/friends", token: token)
    }

    // The route accepts exactly one of `email`/`code` (a zod union) — same
    // "@ means email, else treat as a friend code" split the web client's
    // FriendsPanel.sendRequest uses, so one text field covers both.
    private struct RequestBody: Encodable {
        let email: String?
        let code: String?
    }

    struct SendRequestResponse: Decodable {
        let ok: Bool
        let message: String
    }

    func sendRequest(_ value: String, token: String?) async throws -> SendRequestResponse {
        let isEmail = value.contains("@")
        let body = isEmail
            ? RequestBody(email: value, code: nil)
            : RequestBody(email: nil, code: value)
        return try await client.post("api/friends", body: body, token: token)
    }

    func accept(friendshipId: String, token: String?) async throws {
        try await client.patchDiscardingResponse("api/friends/\(friendshipId)", token: token)
    }

    // Declining a pending request, cancelling one sent, and unfriending an
    // accepted one are all the same call — the route removes the row
    // either way, same as the web client's `remove`.
    func remove(friendshipId: String, token: String?) async throws {
        try await client.deleteDiscardingResponse("api/friends/\(friendshipId)", token: token)
    }
}
