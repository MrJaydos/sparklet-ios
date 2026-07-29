import Foundation

enum CardType: String, Codable {
    case textImage = "TEXT_IMAGE"
    case video = "VIDEO"
}

enum DepthLevel: String, Codable, CaseIterable {
    case simple = "SIMPLE"
    case standard = "STANDARD"
    case deep = "DEEP"
    case extraDeep = "EXTRA_DEEP"
}

struct CardSource: Codable, Hashable {
    let title: String
    let publisher: String
    let url: String
}

struct RelatedLink: Codable, Hashable {
    let id: String
    let title: String
    let icon: String
}

// Mirrors FeedCard in sparklet/src/lib/feed.ts.
struct FeedCard: Codable, Identifiable, Hashable {
    let id: String
    let type: CardType
    let title: String
    let body: String
    let imageUrl: String?
    let videoUrl: String?
    let sources: [CardSource]
    let readMoreUrl: String
    let saved: Bool
    let seen: Bool
    let review: Bool
    let score: Int
    let myVote: Int
    let commentCount: Int
    let depthLevel: DepthLevel
    let category: Category
    let createdAt: String
    let related: [RelatedLink]
}

// Mirrors FeedQuiz.
struct FeedQuiz: Codable, Identifiable, Hashable {
    let id: String
    let question: String
    let options: [String]
    let category: Category
}

// Mirrors FeedReviewQuiz — same shape as FeedQuiz plus the source card it
// reviews; answering it hits /api/reviews/[id]/answer, not /api/quiz.
struct FeedReviewQuiz: Codable, Identifiable, Hashable {
    let id: String
    let question: String
    let options: [String]
    let category: Category
    let sourceCardId: String
}

// Mirrors FeedGuess.
struct FeedGuess: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String
    let min: Double
    let max: Double
    let unit: String
    let integer: Bool
    let category: Category
}

// Mirrors FeedMisconception.
struct FeedMisconception: Codable, Identifiable, Hashable {
    let id: String
    let claim: String
    let category: Category
}

// Mirrors FeedExplainPrompt.
struct FeedExplainPrompt: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let category: Category
}

// Mirrors the object shape returned by GET /api/feed (see
// sparklet/src/app/api/feed/route.ts -> getFeedCards).
struct FeedResponse: Codable {
    let cards: [FeedCard]
    let quizzes: [FeedQuiz]
    let reviewQuizzes: [FeedReviewQuiz]
    let guesses: [FeedGuess]
    let misconceptions: [FeedMisconception]
    let explainPrompts: [FeedExplainPrompt]
    let exhausted: Bool
}
