import XCTest
@testable import Sparklet

final class FeedResponseDecodingTests: XCTestCase {
    // Guards the Codable models against silent drift from the backend
    // shape (sparklet/src/lib/feed.ts's getFeedCards return type).
    func testDecodesAMinimalFeedResponse() throws {
        let json = """
        {
          "cards": [{
            "id": "card1",
            "type": "TEXT_IMAGE",
            "title": "Octopuses have three hearts",
            "body": "Two pump blood to the gills, one to the rest of the body.",
            "imageUrl": null,
            "videoUrl": null,
            "sources": [{ "title": "NOAA", "publisher": "noaa.gov", "url": "https://noaa.gov/octopus" }],
            "readMoreUrl": "https://noaa.gov/octopus",
            "saved": false,
            "seen": false,
            "review": false,
            "score": 3,
            "myVote": 0,
            "commentCount": 0,
            "depthLevel": "STANDARD",
            "category": { "slug": "science", "name": "Science", "colorHex": "#4287f5", "icon": "\\ud83e\\uddea" },
            "createdAt": "2026-07-01T00:00:00.000Z",
            "related": []
          }],
          "quizzes": [],
          "reviewQuizzes": [],
          "guesses": [],
          "misconceptions": [],
          "explainPrompts": [],
          "exhausted": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FeedResponse.self, from: json)
        XCTAssertEqual(response.cards.count, 1)
        XCTAssertEqual(response.cards[0].title, "Octopuses have three hearts")
        XCTAssertEqual(response.cards[0].category.slug, "science")
        XCTAssertFalse(response.exhausted)
    }
}
