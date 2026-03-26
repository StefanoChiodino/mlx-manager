import XCTest
@testable import MLXManager

final class UpdateSchedulerTests: XCTestCase {

    func test_evaluate_nilLastCheck_returnsCheckNow() {
        let result = UpdateScheduler.evaluate(
            interval: 12,
            lastCheck: nil,
            now: Date()
        )
        XCTAssertEqual(result, .checkNow)
    }

    func test_evaluate_intervalZero_returnsDisabled() {
        let result = UpdateScheduler.evaluate(
            interval: 0,
            lastCheck: Date(),
            now: Date()
        )
        XCTAssertEqual(result, .disabled)
    }

    func test_evaluate_elapsedExceedsInterval_returnsCheckNow() {
        let now = Date()
        let lastCheck = now.addingTimeInterval(-13 * 3600) // 13h ago, interval is 12h
        let result = UpdateScheduler.evaluate(
            interval: 12,
            lastCheck: lastCheck,
            now: now
        )
        XCTAssertEqual(result, .checkNow)
    }

    func test_evaluate_elapsedLessThanInterval_returnsScheduleAfter() {
        let now = Date()
        let lastCheck = now.addingTimeInterval(-6 * 3600) // 6h ago, interval is 12h
        let result = UpdateScheduler.evaluate(
            interval: 12,
            lastCheck: lastCheck,
            now: now
        )
        switch result {
        case .scheduleAfter(let delay):
            XCTAssertEqual(delay, 6 * 3600, accuracy: 1.0)
        default:
            XCTFail("Expected .scheduleAfter, got \(result)")
        }
    }

    func test_evaluate_elapsedExactlyAtInterval_returnsCheckNow() {
        let now = Date()
        let lastCheck = now.addingTimeInterval(-12 * 3600)
        let result = UpdateScheduler.evaluate(
            interval: 12,
            lastCheck: lastCheck,
            now: now
        )
        XCTAssertEqual(result, .checkNow)
    }
}
