import XCTest
@testable import MLXManager

// MARK: - Test Doubles

final class MockFileHandle: FileHandleReading {
    var data: Data = Data()
    var currentOffset: UInt64 = 0
    var seekToEndCalled = false

    var offsetInFile: UInt64 { currentOffset }

    @discardableResult
    func seekToEnd() -> UInt64 {
        seekToEndCalled = true
        currentOffset = UInt64(data.count)
        return currentOffset
    }

    func seek(toFileOffset offset: UInt64) {
        currentOffset = offset
    }

    func readDataToEndOfFile() -> Data {
        let start = Int(currentOffset)
        guard start < data.count else { return Data() }
        let result = data[start...]
        currentOffset = UInt64(data.count)
        return Data(result)
    }

    func append(_ string: String) {
        data.append(string.data(using: .utf8)!)
    }
}

final class MockFileWatcher: FileWatcher {
    var handler: (() -> Void)?
    var startCalled = false
    var stopCalled = false
    var shouldSucceed = true

    func startWatching(path: String, handler: @escaping () -> Void) -> Bool {
        startCalled = true
        self.handler = handler
        return shouldSucceed
    }

    func stopWatching() {
        stopCalled = true
        handler = nil
    }

    /// Simulate the file system notifying of a change.
    func simulateChange() {
        handler?()
    }
}

// MARK: - Tests

final class LogTailerTests: XCTestCase {

    private func makeSUT(
        fileHandle: MockFileHandle? = MockFileHandle(),
        watcher: MockFileWatcher = MockFileWatcher(),
        onEvent: @escaping (LogEvent) -> Void = { _ in }
    ) -> (LogTailer, MockFileHandle?, MockFileWatcher) {
        let handle = fileHandle
        let tailer = LogTailer(
            path: "/tmp/test.log",
            fileHandleFactory: { _ in handle },
            watcher: watcher,
            onEvent: onEvent
        )
        return (tailer, handle, watcher)
    }

    // MARK: - 1. start seeks to end

    func test_start_seeksToEndOfFile() {
        let (tailer, handle, _) = makeSUT()
        tailer.start()
        XCTAssertTrue(handle!.seekToEndCalled)
    }

    // MARK: - 2. new lines emitted as events

    func test_newProgressLine_emitsProgressEvent() {
        var events: [LogEvent] = []
        let (tailer, handle, watcher) = makeSUT(onEvent: { events.append($0) })
        tailer.start()

        handle!.append("2026-03-18 23:33:38 - INFO - Prompt processing progress: 4096/41061\n")
        watcher.simulateChange()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first, .progress(current: 4096, total: 41061, percentage: (4096.0 / 41061.0) * 100))
    }

    // MARK: - 3. non-matching lines ignored

    func test_nonMatchingLine_noEventEmitted() {
        var events: [LogEvent] = []
        let (tailer, handle, watcher) = makeSUT(onEvent: { events.append($0) })
        tailer.start()

        handle!.append("Some random log line\n")
        watcher.simulateChange()

        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - 4. multiple lines in one read

    func test_multipleLines_emitsEventsInOrder() {
        var events: [LogEvent] = []
        let (tailer, handle, watcher) = makeSUT(onEvent: { events.append($0) })
        tailer.start()

        handle!.append("2026-03-18 23:33:38 - INFO - Prompt processing progress: 4096/41061\n")
        handle!.append("2026-03-18 23:33:41 - INFO - Prompt processing progress: 8192/41061\n")
        watcher.simulateChange()

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], .progress(current: 4096, total: 41061, percentage: (4096.0 / 41061.0) * 100))
        XCTAssertEqual(events[1], .progress(current: 8192, total: 41061, percentage: (8192.0 / 41061.0) * 100))
    }

    // MARK: - 5. partial line buffered

    func test_partialLine_bufferedUntilNewline() {
        var events: [LogEvent] = []
        let (tailer, handle, watcher) = makeSUT(onEvent: { events.append($0) })
        tailer.start()

        // Append partial line (no newline)
        handle!.append("2026-03-18 23:33:38 - INFO - Prompt processing progress: 4096/41061")
        watcher.simulateChange()
        XCTAssertTrue(events.isEmpty, "Should not emit until newline")

        // Complete the line
        handle!.append("\n")
        watcher.simulateChange()
        XCTAssertEqual(events.count, 1)
    }

    // MARK: - 6. file truncation resets offset

    func test_fileTruncation_resetsOffsetToZero() {
        var events: [LogEvent] = []
        let (tailer, handle, watcher) = makeSUT(onEvent: { events.append($0) })
        tailer.start()

        // Write multiple lines so file is large
        handle!.append("2026-03-18 23:33:38 - INFO - Prompt processing progress: 4096/41061\n")
        handle!.append("2026-03-18 23:33:41 - INFO - Prompt processing progress: 8192/41061\n")
        handle!.append("2026-03-18 23:33:44 - INFO - Prompt processing progress: 12288/41061\n")
        watcher.simulateChange()
        XCTAssertEqual(events.count, 3)

        // Simulate truncation: file shrinks to just one short line
        handle!.data = Data()
        handle!.currentOffset = 0
        handle!.append("2026-03-18 23:34:23 - INFO - KV Caches: 2 seq, 1.75 GB, latest user cache 41056 tokens\n")
        watcher.simulateChange()

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[3], .kvCaches(gpuGB: 1.75, tokens: 41056))
    }

    // MARK: - 7. stop stops watching

    func test_stop_callsStopWatching() {
        let (tailer, _, watcher) = makeSUT()
        tailer.start()
        tailer.stop()
        XCTAssertTrue(watcher.stopCalled)
    }

    // MARK: - 8. file not found at start

    func test_fileNotFound_startIsNoOp() {
        let watcher = MockFileWatcher()
        let tailer = LogTailer(
            path: "/nonexistent",
            fileHandleFactory: { _ in nil },
            watcher: watcher,
            onEvent: { _ in XCTFail("Should not emit events") }
        )
        tailer.start()
        XCTAssertFalse(watcher.startCalled)
    }
}
