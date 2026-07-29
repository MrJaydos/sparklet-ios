import Foundation

// Mirrors GET/POST /api/notifications (sparklet/src/app/api/notifications/route.ts).
struct NotificationsAPI {
    let client: APIClient = .shared

    func fetch(token: String?) async throws -> NotificationsResponse {
        try await client.get("api/notifications", token: token)
    }

    // The route doesn't read the request body — an empty object is sent
    // purely because APIClient.post requires an Encodable body.
    private struct EmptyBody: Encodable {}
    private struct MarkReadResponse: Decodable { let ok: Bool }

    func markAllRead(token: String?) async throws {
        let _: MarkReadResponse = try await client.post("api/notifications", body: EmptyBody(), token: token)
    }
}
