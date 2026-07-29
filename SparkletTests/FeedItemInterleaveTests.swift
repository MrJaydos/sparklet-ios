import XCTest
@testable import Sparklet

// Exercises FeedViewModel.buildItems in isolation — the interleave offsets
// it ports from Feed.tsx have so far only been eyeballed by manually
// swiping the simulator (see AGENTS.md's 2026-07-29 notes), never actually
// asserted against. Pure logic, no network/AuthSession needed.
final class FeedItemInterleaveTests: XCTestCase {
    private let category = Category(slug: "science", name: "Science", colorHex: "#4287f5", icon: "🧪")

    private func makeCards(_ count: Int) -> [FeedCard] {
        (1...count).map { i in
            FeedCard(
                id: "card\(i)",
                type: .textImage,
                title: "Title \(i)",
                body: "Body \(i)",
                imageUrl: nil,
                videoUrl: nil,
                sources: [],
                readMoreUrl: "https://example.com/\(i)",
                saved: false,
                seen: false,
                review: false,
                score: 0,
                myVote: 0,
                commentCount: 0,
                depthLevel: .standard,
                category: category,
                createdAt: "2026-07-01T00:00:00.000Z",
                related: []
            )
        }
    }

    private func makeQuizzes(_ count: Int) -> [FeedQuiz] {
        (1...count).map { FeedQuiz(id: "quiz\($0)", question: "Q\($0)", options: ["a", "b"], category: category) }
    }

    private func makeReviewQuizzes(_ count: Int) -> [FeedReviewQuiz] {
        (1...count).map {
            FeedReviewQuiz(id: "review\($0)", question: "RQ\($0)", options: ["a", "b"], category: category, sourceCardId: "src\($0)")
        }
    }

    private func makeGuesses(_ count: Int) -> [FeedGuess] {
        (1...count).map {
            FeedGuess(id: "guess\($0)", prompt: "G\($0)", min: 0, max: 10, unit: "", integer: true, category: category)
        }
    }

    private func makeMisconceptions(_ count: Int) -> [FeedMisconception] {
        (1...count).map { FeedMisconception(id: "misc\($0)", claim: "C\($0)", category: category) }
    }

    private func makeExplainPrompts(_ count: Int) -> [FeedExplainPrompt] {
        (1...count).map { FeedExplainPrompt(id: "explain\($0)", title: "T\($0)", body: "B\($0)", category: category) }
    }

    func testNoSpecialItemsWhenPoolsAreEmpty() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(5), quizzes: [], reviewQuizzes: [], guesses: [], misconceptions: [], explainPrompts: []
        )
        XCTAssertEqual(items.map(\.id), (1...5).map { "card-card\($0)" })
    }

    // Quiz lands right after the 10th and 20th card (QUIZ_EVERY = 10).
    func testQuizLandsAfterEveryTenthCard() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(20), quizzes: makeQuizzes(2), reviewQuizzes: [], guesses: [], misconceptions: [], explainPrompts: []
        )
        let quizIndices = items.indices.filter { if case .quiz = items[$0] { return true }; return false }
        XCTAssertEqual(quizIndices.count, 2)
        // 10 cards + 1 quiz precede the first quiz slot -> index 10 (0-based).
        XCTAssertEqual(items[quizIndices[0] - 1].id, "card-card10")
        XCTAssertEqual(items[quizIndices[1] - 1].id, "card-card20")
    }

    // Guess lands after card 1 and 13 (GUESS_EVERY = 12, GUESS_OFFSET = 1).
    func testGuessLandsAfterCardOneAndThirteen() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(13), quizzes: [], reviewQuizzes: [], guesses: makeGuesses(2), misconceptions: [], explainPrompts: []
        )
        let guessIndices = items.indices.filter { if case .guess = items[$0] { return true }; return false }
        XCTAssertEqual(guessIndices.count, 2)
        XCTAssertEqual(items[guessIndices[0] - 1].id, "card-card1")
        XCTAssertEqual(items[guessIndices[1] - 1].id, "card-card13")
    }

    // Misconception after card 2 and 12 (MISCONCEPTION_EVERY = 10, OFFSET = 2).
    func testMisconceptionLandsAfterCardTwoAndTwelve() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(12), quizzes: [], reviewQuizzes: [], guesses: [], misconceptions: makeMisconceptions(2), explainPrompts: []
        )
        let miscIndices = items.indices.filter { if case .misconception = items[$0] { return true }; return false }
        XCTAssertEqual(miscIndices.count, 2)
        XCTAssertEqual(items[miscIndices[0] - 1].id, "card-card2")
        XCTAssertEqual(items[miscIndices[1] - 1].id, "card-card12")
    }

    // Explain after card 3 and 15 (EXPLAIN_EVERY = 12, OFFSET = 3).
    func testExplainLandsAfterCardThreeAndFifteen() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(15), quizzes: [], reviewQuizzes: [], guesses: [], misconceptions: [], explainPrompts: makeExplainPrompts(2)
        )
        let explainIndices = items.indices.filter { if case .explain = items[$0] { return true }; return false }
        XCTAssertEqual(explainIndices.count, 2)
        XCTAssertEqual(items[explainIndices[0] - 1].id, "card-card3")
        XCTAssertEqual(items[explainIndices[1] - 1].id, "card-card15")
    }

    // At card 12, only misconception fires — guess's next slot is 13, not
    // 12 — verifying the offsets were actually chosen not to collide, per
    // the comment on buildItems.
    func testSlotsAtSharedPeriodDoNotCollide() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(13),
            quizzes: [],
            reviewQuizzes: [],
            guesses: makeGuesses(2),
            misconceptions: makeMisconceptions(2),
            explainPrompts: [],
            premium: true // isolates interleave-offset logic from ad slots, covered separately below
        )
        let card12Index = items.firstIndex { $0.id == "card-card12" }!
        let card13Index = items.firstIndex { $0.id == "card-card13" }!
        // Exactly one special item between card12 and card13 (the
        // misconception), and it's the misconception, not a guess.
        XCTAssertEqual(card13Index - card12Index, 2)
        if case .misconception = items[card12Index + 1] {} else {
            XCTFail("expected a misconception right after card 12, got \(items[card12Index + 1])")
        }
    }

    // Pool exhaustion: 20 cards means 2 quiz slots (10, 20), but only 1
    // quiz is available — the second slot must be silently skipped, not
    // crash or repeat the first quiz.
    func testStopsInsertingOnceThePoolIsExhausted() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(20), quizzes: makeQuizzes(1), reviewQuizzes: [], guesses: [], misconceptions: [], explainPrompts: [],
            premium: true // isolates pool-exhaustion logic from ad slots, covered separately below
        )
        let quizIndices = items.indices.filter { if case .quiz = items[$0] { return true }; return false }
        XCTAssertEqual(quizIndices.count, 1)
        XCTAssertEqual(items.count, 21) // 20 cards + 1 quiz, nothing more.
    }

    // reviewQuizzes get an even spread across the whole batch rather than a
    // fixed period: with 9 cards and 2 reviewQuizzes, positions are
    // round(9/3)=3 and round(18/3)=6, each flushed just BEFORE that card.
    func testReviewQuizzesSpreadEvenlyAndFlushBeforeTheirCard() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(9), quizzes: [], reviewQuizzes: makeReviewQuizzes(2), guesses: [], misconceptions: [], explainPrompts: [],
            premium: true // isolates review-quiz spread logic from ad slots, covered separately below
        )
        XCTAssertEqual(
            items.map(\.id),
            [
                "card-card1", "card-card2",
                "reviewQuiz-review1", "card-card3",
                "card-card4", "card-card5",
                "reviewQuiz-review2", "card-card6",
                "card-card7", "card-card8", "card-card9",
            ]
        )
    }

    // Only a `.card` should ever be eligible for read-tracking — every
    // special item type must report nil, or trackView would fabricate a
    // read for a quiz/guess/misconception/explain slot nobody read.
    func testOnlyCardsAreEligibleForReadTracking() {
        // 15 cards is enough for every slot type (quiz@10, guess@1/13,
        // misconception@2/12, explain@3/15) to actually appear at least
        // once, plus a couple of reviewQuizzes spread through the batch.
        let items = FeedViewModel.buildItems(
            cards: makeCards(15),
            quizzes: makeQuizzes(1),
            reviewQuizzes: makeReviewQuizzes(2),
            guesses: makeGuesses(1),
            misconceptions: makeMisconceptions(1),
            explainPrompts: makeExplainPrompts(1)
        )
        // Sanity check every kind actually showed up — otherwise the loop
        // below would trivially pass without exercising anything.
        XCTAssertTrue(items.contains { if case .quiz = $0 { return true }; return false })
        XCTAssertTrue(items.contains { if case .reviewQuiz = $0 { return true }; return false })
        XCTAssertTrue(items.contains { if case .guess = $0 { return true }; return false })
        XCTAssertTrue(items.contains { if case .misconception = $0 { return true }; return false })
        XCTAssertTrue(items.contains { if case .explain = $0 { return true }; return false })

        for item in items {
            switch item {
            case .card(let c):
                XCTAssertEqual(item.cardIdForReadTracking, c.id)
            default:
                XCTAssertNil(item.cardIdForReadTracking, "\(item) must not be read-trackable")
            }
        }
    }

    // Ad lands after every 6th card (AD_EVERY = 6) for a free-tier user —
    // mirrors Feed.tsx/AdSlide.tsx's own placement.
    func testAdLandsAfterEverySixthCardForFreeTier() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(12), quizzes: [], reviewQuizzes: [], guesses: [], misconceptions: [], explainPrompts: [],
            premium: false
        )
        let adIndices = items.indices.filter { if case .ad = items[$0] { return true }; return false }
        XCTAssertEqual(adIndices.count, 2)
        XCTAssertEqual(items[adIndices[0] - 1].id, "card-card6")
        XCTAssertEqual(items[adIndices[1] - 1].id, "card-card12")
    }

    // Never pushed at all for premium users — no dead ad slide in a paying
    // user's scroll, per the comment on buildItems.
    func testNoAdsForPremiumUsers() {
        let items = FeedViewModel.buildItems(
            cards: makeCards(12), quizzes: [], reviewQuizzes: [], guesses: [], misconceptions: [], explainPrompts: [],
            premium: true
        )
        XCTAssertFalse(items.contains { if case .ad = $0 { return true }; return false })
    }
}
