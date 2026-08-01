import XCTest
@testable import Sparklet

final class DepthPreferenceTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "sparklet.depth")
        super.tearDown()
    }

    func testNeverSetReturnsNil() {
        XCTAssertNil(DepthPreference.get())
    }

    func testSetThenGetRoundTrips() {
        DepthPreference.set(.extraDeep)
        XCTAssertEqual(DepthPreference.get(), .extraDeep)
    }

    func testSetCanBeResetToStandard() {
        DepthPreference.set(.deep)
        DepthPreference.set(.standard)
        XCTAssertEqual(DepthPreference.get(), .standard)
    }
}
