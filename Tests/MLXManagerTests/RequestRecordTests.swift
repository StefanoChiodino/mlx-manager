import XCTest
@testable import MLXManager

final class RequestRecordTests: XCTestCase {

    func test_requestRecord_duration() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end   = Date(timeIntervalSinceReferenceDate: 45)
        let r = RequestRecord(startedAt: start, completedAt: end, tokens: 1234)
        XCTAssertEqual(r.duration, 45, accuracy: 0.001)
        XCTAssertEqual(r.tokens, 1234)
    }

    // MARK: ServerState — completedRequest on KV completion

    func test_serverState_completedRequest_setOnKVCompletion() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 1000, total: 5000, percentage: 20.0))
        state.handle(.kvCaches(gpuGB: 1.5, tokens: 5000))
        XCTAssertNotNil(state.completedRequest)
        XCTAssertEqual(state.completedRequest?.tokens, 5000)
    }

    func test_serverState_completedRequest_setOnHTTPCompletion() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97))
        state.handle(.httpCompletion)
        XCTAssertNotNil(state.completedRequest)
    }

    func test_serverState_completedRequest_nilIfNoProgress() {
        // Completion signal with no prior progress → no record (nothing started)
        var state = ServerState()
        state.serverStarted()
        state.handle(.kvCaches(gpuGB: 0, tokens: 0))
        XCTAssertNil(state.completedRequest)
    }

    func test_serverState_clearCompletedRequest() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 100, total: 200, percentage: 50.0))
        state.handle(.httpCompletion)
        XCTAssertNotNil(state.completedRequest)
        state.clearCompletedRequest()
        XCTAssertNil(state.completedRequest)
    }
}
