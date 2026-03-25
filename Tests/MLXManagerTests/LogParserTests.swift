import XCTest
@testable import MLXManager

final class LogParserTests: XCTestCase {

    // MARK: - Progress lines

    /// Spec: Valid progress line — mid-request
    func test_parse_progressLine_returnsMidRequestEvent() {
        let line = "2026-03-18 23:33:38,553 - INFO - Prompt processing progress: 4096/41061"
        let result = LogParser.parse(line: line)
        guard case .progress(let current, let total, let percentage, let timestamp) = result else {
            XCTFail("Expected .progress, got \(String(describing: result))")
            return
        }
        XCTAssertNotNil(timestamp)
        XCTAssertEqual(current, 4096)
        XCTAssertEqual(total, 41061)
        XCTAssertEqual(percentage, (4096.0 / 41061.0) * 100, accuracy: 0.01)
    }

    /// Spec: Valid progress line — near end (realistic maximum)
    /// Completion is NOT inferred from progress alone — current==total never occurs in practice.
    func test_parse_progressNearEnd_returnsEventWithHighPercentage() {
        let line = "2026-03-18 23:34:18,156 - INFO - Prompt processing progress: 41056/41061"
        let result = LogParser.parse(line: line)
        guard case .progress(let current, let total, let percentage, let timestamp) = result else {
            XCTFail("Expected .progress, got \(String(describing: result))")
            return
        }
        XCTAssertNotNil(timestamp)
        XCTAssertEqual(current, 41056)
        XCTAssertEqual(total, 41061)
        XCTAssertEqual(percentage, (41056.0 / 41061.0) * 100, accuracy: 0.01)
    }

    /// Spec: Non-progress line → nil when parsing for progress
    func test_parse_kvCachesLine_returnsNilForProgressParser() {
        let line = "2026-03-18 23:34:23,603 - INFO - KV Caches: 4 seq, 1.94 GB, latest user cache 25724 tokens"
        let result = LogParser.parse(line: line)
        if case .progress = result {
            XCTFail("KV Caches line should not parse as .progress")
        }
    }

    // MARK: - KV Caches lines

    /// Spec: Valid KV Caches line
    func test_parse_kvCachesLine_returnsGpuAndTokens() {
        let line = "2026-03-18 23:48:12,000 - INFO - KV Caches: 4 seq, 1.94 GB, latest user cache 25724 tokens"
        let result = LogParser.parse(line: line)
        guard case .kvCaches(let gpuGB, let tokens) = result else {
            XCTFail("Expected .kvCaches, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(gpuGB, 1.94, accuracy: 0.001)
        XCTAssertEqual(tokens, 25724)
    }

    /// Spec: KV Caches with zero values (server start / cache flush)
    func test_parse_kvCachesZero_returnsZeroValues() {
        let line = "2026-03-18 23:33:34,979 - INFO - KV Caches: 0 seq, 0.00 GB, latest user cache 0 tokens"
        let result = LogParser.parse(line: line)
        guard case .kvCaches(let gpuGB, let tokens) = result else {
            XCTFail("Expected .kvCaches, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(gpuGB, 0.0, accuracy: 0.001)
        XCTAssertEqual(tokens, 0)
    }

    // MARK: - KV Caches — new format (no seq count)

    /// New format: "KV Caches: ... X.XX GB, latest user cache N tokens"
    func test_parse_kvCachesNewFormat_returnsGpuAndTokens() {
        let line = "KV Caches: ... 1.54 GB, latest user cache 9826 tokens"
        let result = LogParser.parse(line: line)
        guard case .kvCaches(let gpuGB, let tokens) = result else {
            XCTFail("Expected .kvCaches, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(gpuGB, 1.54, accuracy: 0.001)
        XCTAssertEqual(tokens, 9826)
    }

    /// New format: zero values
    func test_parse_kvCachesNewFormatZero_returnsZeroValues() {
        let line = "KV Caches: ... 0.00 GB, latest user cache 0 tokens"
        let result = LogParser.parse(line: line)
        guard case .kvCaches(let gpuGB, let tokens) = result else {
            XCTFail("Expected .kvCaches, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(gpuGB, 0.0, accuracy: 0.001)
        XCTAssertEqual(tokens, 0)
    }

    /// Old format regression: "KV Caches: N seq, X.XX GB, N tokens" must still parse
    func test_parse_kvCachesOldFormat_regression() {
        let line = "KV Caches: 2 seq, 1.54 GB, 4096 tokens"
        let result = LogParser.parse(line: line)
        guard case .kvCaches(let gpuGB, let tokens) = result else {
            XCTFail("Expected .kvCaches, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(gpuGB, 1.54, accuracy: 0.001)
        XCTAssertEqual(tokens, 4096)
    }

    /// Spec: Non-KV line → not a kvCaches event
    func test_parse_progressLine_returnsNilForKvParser() {
        let line = "2026-03-18 23:33:38,553 - INFO - Prompt processing progress: 4096/41061"
        let result = LogParser.parse(line: line)
        if case .kvCaches = result {
            XCTFail("Progress line should not parse as .kvCaches")
        }
    }

    // MARK: - HTTP completion lines

    /// Spec: HTTP 200 completion line
    func test_parse_http200Line_returnsHttpCompletion() {
        let line = "127.0.0.1 - - [18/Mar/2026 23:34:23] \"POST /v1/chat/completions HTTP/1.1\" 200 -"
        let result = LogParser.parse(line: line)
        XCTAssertEqual(result, .httpCompletion)
    }

    /// Spec: Non-completion HTTP line (GET, not POST to completions)
    func test_parse_httpGetLine_returnsNil() {
        let line = "2026-03-18 23:32:48,742 - INFO - HTTP Request: GET https://huggingface.co/api/models/mlx-community/Qwen3.5-35B-A3B-4bit/revision/main \"HTTP/1.1 200 OK\""
        XCTAssertNil(LogParser.parse(line: line))
    }

    // MARK: - Ignored lines

    /// Spec: Fetching lines (model download progress bars)
    func test_parse_ignoredLine_fetching_returnsNil() {
        let line = "Fetching 14 files: 100%|██████████| 14/14 [00:00<00:00, 79137.81it/s]"
        XCTAssertNil(LogParser.parse(line: line))
    }

    /// Spec: WARNING lines
    func test_parse_ignoredLine_warning_returnsNil() {
        let line = "/Users/stefano/repos/mlx/venv/lib/python3.12/site-packages/mlx_lm/server.py:1858: UserWarning: mlx_lm.server is not recommended for production as it only implements basic security checks."
        XCTAssertNil(LogParser.parse(line: line))
    }

    /// Spec: resource_tracker lines
    func test_parse_ignoredLine_resourceTracker_returnsNil() {
        let line = "/opt/homebrew/Cellar/python@3.12/3.12.13/Frameworks/Python.framework/Versions/3.12/lib/python3.12/multiprocessing/resource_tracker.py:279: UserWarning: resource_tracker: There appear to be 1 leaked semaphore objects to clean up at shutdown"
        XCTAssertNil(LogParser.parse(line: line))
    }

    /// Spec: Starting httpd lines
    func test_parse_ignoredLine_startingHttpd_returnsNil() {
        let line = "2026-03-18 23:32:50,900 - INFO - Starting httpd at 127.0.0.1 on port 8081..."
        XCTAssertNil(LogParser.parse(line: line))
    }

    /// Spec: HuggingFace HTTP GET model check lines
    func test_parse_ignoredLine_hfModelCheck_returnsNil() {
        let line = "2026-03-18 23:32:48,742 - INFO - HTTP Request: GET https://huggingface.co/api/models/mlx-community/Qwen3.5-35B-A3B-4bit/revision/main \"HTTP/1.1 200 OK\""
        XCTAssertNil(LogParser.parse(line: line))
    }
}

import Testing

@Test("LogLineKind maps progress event")
func logLineKindMapsProgress() {
    let kind = LogLineKind(.progress(current: 1, total: 10, percentage: 10.0, timestamp: Date()))
    #expect(kind == .progress)
}

@Test("LogLineKind maps kvCaches event")
func logLineKindMapsKvCaches() {
    let kind = LogLineKind(.kvCaches(gpuGB: 1.0, tokens: 100))
    #expect(kind == .kvCaches)
}

@Test("LogLineKind maps httpCompletion event")
func logLineKindMapsHttpCompletion() {
    let kind = LogLineKind(.httpCompletion)
    #expect(kind == .httpCompletion)
}
