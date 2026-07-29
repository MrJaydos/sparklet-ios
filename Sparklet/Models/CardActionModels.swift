import Foundation

// Mirrors POST /api/cards/[id]/vote's response (sparklet repo).
struct VoteResponse: Decodable {
    let score: Int
    let myVote: Int
}

// Mirrors POST /api/cards/[id]/save's response.
struct SaveResponse: Decodable {
    let saved: Bool
}

// Mirrors a comment object from GET/POST /api/cards/[id]/comments.
struct Comment: Decodable, Identifiable, Hashable {
    let id: String
    let body: String
    let createdAt: String
    let author: String
    let mine: Bool
}

struct CommentsResponse: Decodable {
    let comments: [Comment]
}

struct PostCommentResponse: Decodable {
    let comment: Comment
}

// Mirrors POST /api/report's body reason enum.
enum ReportReason: String, CaseIterable {
    case incorrect = "INCORRECT"
    case inappropriate = "INAPPROPRIATE"
    case spam = "SPAM"
    case other = "OTHER"

    // Matches ReportSheet.tsx's REASONS copy exactly.
    var label: String {
        switch self {
        case .incorrect: return "❌ Factually incorrect"
        case .inappropriate: return "⚠️ Inappropriate"
        case .spam: return "🗑️ Spam"
        case .other: return "💬 Something else"
        }
    }
}

struct ReportResponse: Decodable {
    let ok: Bool
    let alreadyReported: Bool?
}

// Mirrors POST /api/cards/[id]/depth's response — the returned card's own
// `id` is deliberately unused client-side (see CardView): the web only
// swaps the displayed title/body, every action (vote/save/comment/report)
// keeps targeting the original standard card's id.
struct DepthCardResponse: Decodable {
    struct CardVariant: Decodable {
        let id: String
        let title: String
        let body: String
        let depthLevel: DepthLevel
    }
    let card: CardVariant
    let generated: Bool
}
