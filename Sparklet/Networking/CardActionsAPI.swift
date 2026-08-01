import Foundation

// Mirrors sparklet/src/app/api/cards/[id]/{vote,save,comments,depth}/route.ts
// and /api/report/route.ts.
struct CardActionsAPI {
    let client: APIClient = .shared

    // GET /api/cards/[id] (sparklet repo) — single-card lookup for
    // CardDetailView, returned in the same FeedCard shape the feed endpoint
    // already uses so this decodes straight into the existing model.
    func fetchCard(cardId: String, token: String?) async throws -> FeedCard {
        try await client.get("api/cards/\(cardId)", token: token)
    }

    private struct VoteRequest: Encodable { let value: Int }
    func vote(cardId: String, value: Int, token: String?) async throws -> VoteResponse {
        try await client.post("api/cards/\(cardId)/vote", body: VoteRequest(value: value), token: token)
    }

    private struct SaveRequest: Encodable { let saved: Bool }
    func setSaved(cardId: String, saved: Bool, token: String?) async throws -> SaveResponse {
        try await client.post("api/cards/\(cardId)/save", body: SaveRequest(saved: saved), token: token)
    }

    func fetchComments(cardId: String, token: String?) async throws -> CommentsResponse {
        try await client.get("api/cards/\(cardId)/comments", token: token)
    }

    private struct PostCommentRequest: Encodable { let body: String }
    func postComment(cardId: String, body: String, token: String?) async throws -> Comment {
        let response: PostCommentResponse = try await client.post(
            "api/cards/\(cardId)/comments",
            body: PostCommentRequest(body: body),
            token: token
        )
        return response.comment
    }

    // Exactly one of cardId/commentId must be set — synthesized Encodable
    // omits a nil Optional via encodeIfPresent (see AnswersAPI's
    // ExplainAnswerRequest comment), matching the backend's zod .refine.
    private struct ReportRequest: Encodable {
        let cardId: String?
        let commentId: String?
        let reason: String
        let detail: String?
    }

    func reportCard(cardId: String, reason: ReportReason, detail: String?, token: String?) async throws -> ReportResponse {
        try await client.post(
            "api/report",
            body: ReportRequest(cardId: cardId, commentId: nil, reason: reason.rawValue, detail: detail),
            token: token
        )
    }

    func reportComment(commentId: String, reason: ReportReason, detail: String?, token: String?) async throws -> ReportResponse {
        try await client.post(
            "api/report",
            body: ReportRequest(cardId: nil, commentId: commentId, reason: reason.rawValue, detail: detail),
            token: token
        )
    }

    // Throws APIError.server(status: 402, ...) when the level is premium-
    // gated and the caller isn't subscribed — see CardView's handling.
    private struct DepthRequest: Encodable { let level: String }
    func fetchDepth(cardId: String, level: DepthLevel, token: String?) async throws -> DepthCardResponse {
        try await client.post("api/cards/\(cardId)/depth", body: DepthRequest(level: level.rawValue), token: token)
    }
}
