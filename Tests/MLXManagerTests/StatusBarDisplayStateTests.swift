import XCTest
@testable import MLXManager

final class StatusBarDisplayStateTests: XCTestCase {

    func test_statusBarDisplayState_exists() {
        let offline = StatusBarDisplayState.offline
        let idle = StatusBarDisplayState.idle
        let processing = StatusBarDisplayState.processing(fraction: 0.67)
        let failed = StatusBarDisplayState.failed

        XCTAssertEqual(offline, .offline)
        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(processing, .processing(fraction: 0.67))
        XCTAssertEqual(failed, .failed)
    }
}
