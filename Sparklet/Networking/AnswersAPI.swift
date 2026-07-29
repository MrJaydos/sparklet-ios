import Foundation

// Mirrors POST /api/quiz/[id]/answer, /api/reviews/[id]/answer,
// /api/guess/[id]/answer, /api/misconception/[id]/answer, and
// /api/explain/[cardId]/answer (sparklet/src/app/api/**/answer/route.ts).
struct AnswersAPI {
    let client: APIClient = .shared

    // Same JS Date.getTimezoneOffset() sign convention as
    // FeedAPI.postInteraction — see the comment there. Every answer route
    // takes this to bucket combo/XP into the user's own local day.
    private var tzOffsetMinutes: Int {
        TimeZone.current.secondsFromGMT() / -60
    }

    private struct IndexAnswerRequest: Encodable {
        let index: Int
        let tzOffsetMinutes: Int
    }

    func answerQuiz(id: String, index: Int, token: String?) async throws -> QuizAnswerResponse {
        try await client.post(
            "api/quiz/\(id)/answer",
            body: IndexAnswerRequest(index: index, tzOffsetMinutes: tzOffsetMinutes),
            token: token
        )
    }

    // Reviews recur by design, so unlike answerQuiz this pays XP every time
    // (see the comment on POST /api/reviews/[id]/answer) — the server also
    // 409s if the underlying card isn't actually due, so a stale/replayed
    // review surfaces as a thrown APIError.server rather than silent no-op.
    func answerReview(id: String, index: Int, token: String?) async throws -> QuizAnswerResponse {
        try await client.post(
            "api/reviews/\(id)/answer",
            body: IndexAnswerRequest(index: index, tzOffsetMinutes: tzOffsetMinutes),
            token: token
        )
    }

    private struct GuessAnswerRequest: Encodable {
        let guess: Double
        let tzOffsetMinutes: Int
    }

    func answerGuess(id: String, guess: Double, token: String?) async throws -> GuessAnswerResponse {
        try await client.post(
            "api/guess/\(id)/answer",
            body: GuessAnswerRequest(guess: guess, tzOffsetMinutes: tzOffsetMinutes),
            token: token
        )
    }

    private struct BoolAnswerRequest: Encodable {
        let guess: Bool
        let tzOffsetMinutes: Int
    }

    func answerMisconception(id: String, guess: Bool, token: String?) async throws -> MisconceptionAnswerResponse {
        try await client.post(
            "api/misconception/\(id)/answer",
            body: BoolAnswerRequest(guess: guess, tzOffsetMinutes: tzOffsetMinutes),
            token: token
        )
    }

    // `text`/`skip` are both optional on the wire (zod's .refine requires
    // exactly one) — synthesized Encodable omits nil Optional fields via
    // encodeIfPresent, so passing nil for the other actually leaves it off
    // the JSON body rather than sending an explicit null.
    private struct ExplainAnswerRequest: Encodable {
        let text: String?
        let skip: Bool?
        let tzOffsetMinutes: Int
    }

    func answerExplain(cardId: String, text: String, token: String?) async throws -> ExplainAnswerResponse {
        try await client.post(
            "api/explain/\(cardId)/answer",
            body: ExplainAnswerRequest(text: text, skip: nil, tzOffsetMinutes: tzOffsetMinutes),
            token: token
        )
    }

    func skipExplain(cardId: String, token: String?) async throws -> ExplainAnswerResponse {
        try await client.post(
            "api/explain/\(cardId)/answer",
            body: ExplainAnswerRequest(text: nil, skip: true, tzOffsetMinutes: tzOffsetMinutes),
            token: token
        )
    }
}
