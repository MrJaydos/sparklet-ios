import Foundation

// Mirrors GET /api/categories and POST /api/interests
// (sparklet/src/app/api/categories/route.ts, .../interests/route.ts).
struct OnboardingAPI {
    let client: APIClient = .shared

    private struct CategoriesResponse: Decodable { let categories: [Category] }

    // No auth required — same query the web's onboarding and signed-out
    // feed pages already run server-side.
    func fetchCategories(token: String?) async throws -> [Category] {
        let response: CategoriesResponse = try await client.get("api/categories", token: token)
        return response.categories
    }

    // Submitting an empty selection (the "show me everything" skip) still
    // completes onboarding server-side — see the route's own comment.
    private struct InterestsRequest: Encodable { let categorySlugs: [String] }
    private struct InterestsResponse: Decodable { let ok: Bool }

    func submitInterests(categorySlugs: [String], token: String?) async throws {
        let _: InterestsResponse = try await client.post(
            "api/interests",
            body: InterestsRequest(categorySlugs: categorySlugs),
            token: token
        )
    }
}
