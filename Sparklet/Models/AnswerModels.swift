import Foundation

// Shared response shape for POST /api/quiz/[id]/answer and
// POST /api/reviews/[id]/answer (sparklet/src/app/api/quiz/[id]/answer,
// .../reviews/[id]/answer) — identical fields; the review route just omits
// `sourceCardId`, left optional here rather than a second near-duplicate type.
struct QuizAnswerResponse: Decodable {
    let correct: Bool
    let correctIndex: Int
    let explanation: String
    let sourceCardId: String?
    let xp: XpSummary
    let combo: Int
    let multiplier: Double
    let guest: Bool?
}

// Mirrors POST /api/guess/[id]/answer's response.
struct GuessAnswerResponse: Decodable {
    let answer: Double
    let accuracy: Double
    let correct: Bool
    let explanation: String
    let sourceCardId: String
    let xp: XpSummary
    let combo: Int
    let multiplier: Double
    let guest: Bool?
}

// Mirrors POST /api/misconception/[id]/answer's response.
struct MisconceptionAnswerResponse: Decodable {
    let answer: Bool
    let correct: Bool
    let explanation: String
    let sourceCardId: String
    let xp: XpSummary
    let combo: Int
    let multiplier: Double
    let guest: Bool?
}

// Mirrors POST /api/explain/[cardId]/answer's response — no correct/combo,
// just a continuous 0-1 score (see gradeExplanation in sparklet/src/lib/
// grade-explanation.ts).
struct ExplainAnswerResponse: Decodable {
    let score: Double
    let feedback: String
    let xp: XpSummary
}
