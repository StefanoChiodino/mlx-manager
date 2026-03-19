import XCTest
@testable import MLXManager

final class RAMPollerTests: XCTestCase {

    func test_ramPoller_emitsSampleWithMockProvider() {
        // Stub returns 4 GB (4 * 1024^3 bytes)
        let expectedBytes: UInt64 = 4 * 1024 * 1024 * 1024
        let stub = StubPIDInfoProvider(rssBytes: expectedBytes)
        let poller = RAMPoller(pid: 999, interval: 0.01, provider: stub)

        let expectation = expectation(description: "sample received")
        poller.onSample = { sample in
            XCTAssertEqual(sample.gb, Double(expectedBytes) / 1_073_741_824, accuracy: 0.001)
            expectation.fulfill()
        }

        poller.start()
        wait(for: [expectation], timeout: 1.0)
        poller.stop()
    }

    func test_ramPoller_stopPreventsMoreSamples() {
        let stub = StubPIDInfoProvider(rssBytes: 1024)
        let poller = RAMPoller(pid: 999, interval: 0.01, provider: stub)
        var count = 0
        poller.onSample = { _ in count += 1 }

        poller.start()
        Thread.sleep(forTimeInterval: 0.025)
        poller.stop()
        let countAfterStop = count
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(count, countAfterStop)
    }
}

// MARK: - Test double

final class StubPIDInfoProvider: PIDInfoProvider {
    private let rssBytes: UInt64
    init(rssBytes: UInt64) { self.rssBytes = rssBytes }
    func residentSetBytes(pid: Int32) -> UInt64 { rssBytes }
}
