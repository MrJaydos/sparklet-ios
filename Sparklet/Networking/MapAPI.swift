import Foundation

// Mirrors GET /api/map (sparklet/src/app/api/map/route.ts).
struct MapAPI {
    let client: APIClient = .shared

    func fetch(token: String?) async throws -> MapResponse {
        try await client.get("api/map", token: token)
    }
}
