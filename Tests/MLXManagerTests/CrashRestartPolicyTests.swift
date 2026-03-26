import XCTest
@testable import MLXManager

final class CrashRestartPolicyTests: XCTestCase {

    func test_recordCrash_firstCrash_returnsTrue() {
        var policy = CrashRestartPolicy()
        let allowed = policy.recordCrash(at: Date())
        XCTAssertTrue(allowed)
    }

    func test_recordCrash_thirdCrashDenied() {
        var policy = CrashRestartPolicy(maxRestarts: 3, window: 180)
        let now = Date()
        XCTAssertTrue(policy.recordCrash(at: now))
        XCTAssertTrue(policy.recordCrash(at: now.addingTimeInterval(1)))
        let third = policy.recordCrash(at: now.addingTimeInterval(2))
        XCTAssertFalse(third)
    }

    func test_recordCrash_oldCrashesEvicted_allowsRestart() {
        var policy = CrashRestartPolicy(maxRestarts: 3, window: 180)
        let now = Date()
        _ = policy.recordCrash(at: now)
        _ = policy.recordCrash(at: now.addingTimeInterval(1))
        let allowed = policy.recordCrash(at: now.addingTimeInterval(200))
        XCTAssertTrue(allowed)
    }

    func test_reset_clearsCrashHistory() {
        var policy = CrashRestartPolicy(maxRestarts: 3, window: 180)
        let now = Date()
        _ = policy.recordCrash(at: now)
        _ = policy.recordCrash(at: now.addingTimeInterval(1))
        policy.reset()
        XCTAssertTrue(policy.crashTimestamps.isEmpty)
        XCTAssertTrue(policy.recordCrash(at: now.addingTimeInterval(2)))
    }
}
