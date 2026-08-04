import XCTest
@testable import Sparklet

final class AuthCallbackTests: XCTestCase {
    func testExtractsCodeFromTheAuthRedirect() {
        let url = URL(string: "sparklet-ios://auth?code=abc123")!
        XCTAssertEqual(AuthCallback.code(from: url), "abc123")
    }

    func testRejectsOtherHosts() {
        // Same scheme, different host — e.g. a hypothetical future
        // sparklet-ios://something-else link shouldn't be mistaken for an
        // auth callback just because it shares the custom scheme.
        XCTAssertNil(AuthCallback.code(from: URL(string: "sparklet-ios://invite?code=abc123")!))
    }

    func testRejectsAMissingCode() {
        XCTAssertNil(AuthCallback.code(from: URL(string: "sparklet-ios://auth")!))
    }
}
