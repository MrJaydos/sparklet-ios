import Foundation

// The feed API returns cards/quizzes/reviewQuizzes/guesses/misconceptions/
// explainPrompts as separate pools — nothing on the wire says where a quiz
// or guess belongs relative to a card. The web client (Feed.tsx) interleaves
// them into one sequence client-side; FeedViewModel.buildItems ports that
// same interleave so the rhythm of quiz/guess/misconception/explain slots
// matches across platforms.
enum FeedItem: Identifiable, Hashable {
    // `occurrence` is the card's index in FeedViewModel's cumulative `cards`
    // pool at the moment it was interleaved in — cards only ever repeat
    // client-side once a session runs out of unseen content and starts
    // recirculating previously-seen ones (see FeedViewModel's `exhausted`/
    // allowRepeats handling), so the SAME underlying card.id can legitimately
    // appear at two different positions in one session's `items` array.
    // Without this, both occurrences would produce an identical `id`,
    // breaking SwiftUI's ForEach/.scrollPosition(id:) uniqueness requirement
    // (and, worse, silently misattributing read-tracking to the wrong
    // occurrence). The index is stable across rebuilds because `cards` only
    // ever grows by appending — never reorders or removes.
    case card(FeedCard, occurrence: Int)
    case quiz(FeedQuiz)
    case reviewQuiz(FeedReviewQuiz)
    case guess(FeedGuess)
    case misconception(FeedMisconception)
    case explain(FeedExplainPrompt)
    // No server-side model — mirrors Feed.tsx's `{ kind: "ad", adKey }`,
    // a client-side-only slide inserted by the interleave, never fetched.
    case ad(key: Int)

    var id: String {
        switch self {
        case .card(let c, let occurrence): return "card-\(c.id)-\(occurrence)"
        case .quiz(let q): return "quiz-\(q.id)"
        case .reviewQuiz(let q): return "reviewQuiz-\(q.id)"
        case .guess(let g): return "guess-\(g.id)"
        case .misconception(let m): return "misconception-\(m.id)"
        case .explain(let e): return "explain-\(e.id)"
        case .ad(let key): return "ad-\(key)"
        }
    }

    // Only a `.card` counts toward the read-tracking dwell flow — quizzes/
    // guesses/misconceptions/explain prompts are only ever served for cards
    // already read (or, for guess/misconception, deliberately unseen — see
    // sparklet/src/lib/feed.ts), so they earn XP through their own answer
    // endpoint, never through /api/interactions.
    var cardIdForReadTracking: String? {
        if case .card(let c, _) = self { return c.id }
        return nil
    }
}
