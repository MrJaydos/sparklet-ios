import XCTest
@testable import Sparklet

final class DailyCardGoalTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "sparklet.dailyGoal")
        UserDefaults.standard.removeObject(forKey: "sparklet.goalHit")
        super.tearDown()
    }

    func testCurrentDefaultsWhenNeverSet() {
        XCTAssertEqual(DailyCardGoal.current, DailyCardGoal.defaultGoal)
    }

    func testCurrentReflectsAStoredValue() {
        UserDefaults.standard.set(25, forKey: "sparklet.dailyGoal")
        XCTAssertEqual(DailyCardGoal.current, 25)
    }

    // Mirrors Feed.tsx's GOAL_HIT_KEY date guard — the celebration fires at
    // most once per local calendar day.
    func testMarkReachedFiresOnceThenSuppressesSameDayReplays() {
        XCTAssertTrue(DailyCardGoal.markReachedIfNeededToday())
        XCTAssertFalse(DailyCardGoal.markReachedIfNeededToday())
        XCTAssertFalse(DailyCardGoal.markReachedIfNeededToday())
    }
}
