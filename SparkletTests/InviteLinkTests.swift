import XCTest
@testable import Sparklet

final class InviteLinkTests: XCTestCase {
    func testExtractsRefIdFromAUniversalLink() {
        let url = URL(string: "https://sparkletapp.com/invite/cabc123")!
        XCTAssertEqual(InviteLink.refId(from: url), "cabc123")
    }

    func testExtractsRefIdRegardlessOfHost() {
        // Same path shape delivered via `xcrun simctl openurl` in dev,
        // where the app has no signed apple-app-site-association yet — see
        // project.yml's entitlements comment.
        let url = URL(string: "https://localhost:3001/invite/cabc123")!
        XCTAssertEqual(InviteLink.refId(from: url), "cabc123")
    }

    func testRejectsUnrelatedPaths() {
        XCTAssertNil(InviteLink.refId(from: URL(string: "https://sparkletapp.com/feed")!))
        XCTAssertNil(InviteLink.refId(from: URL(string: "https://sparkletapp.com/")!))
        XCTAssertNil(InviteLink.refId(from: URL(string: "https://sparkletapp.com/invite/cabc123/extra")!))
    }
}
