import XCTest
@testable import MLXManager

final class LogLineStripperTests: XCTestCase {

    // MARK: - mlx_lm.server prefix (datetime + INFO)

    func test_strip_removesDatetimeInfoPrefix() {
        let raw = "2026-03-22 10:09:07,338 - INFO - Prompt processing progress: 4096/24378"
        let result = LogLineStripper.strip(raw, event: nil)
        XCTAssertEqual(result, "Prompt processing progress: 4096/24378")
    }

    func test_strip_removesDatetimeInfoPrefix_differentTimestamp() {
        let raw = "2026-01-01 00:00:00,000 - INFO - KV Caches: 0 seq, 0.00 GB"
        let result = LogLineStripper.strip(raw, event: nil)
        XCTAssertEqual(result, "KV Caches: 0 seq, 0.00 GB")
    }

    // MARK: - Vision/uvicorn prefix (INFO:     )

    func test_strip_removesUvicornInfoPrefix() {
        let raw = "INFO:     Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)"
        let result = LogLineStripper.strip(raw, event: nil)
        XCTAssertEqual(result, "Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)")
    }

    func test_strip_removesUvicornInfoPrefix_singleSpace() {
        let raw = "INFO: Application startup complete."
        let result = LogLineStripper.strip(raw, event: nil)
        XCTAssertEqual(result, "Application startup complete.")
    }

    // MARK: - No prefix — leave unchanged

    func test_strip_noPrefix_leftUnchanged() {
        let raw = "Prefill: 100%|█████████▉| 23214/23215 [00:21<00:00, 1081.82tok/s]"
        let result = LogLineStripper.strip(raw, event: nil)
        XCTAssertEqual(result, "Prefill: 100%|█████████▉| 23214/23215 [00:21<00:00, 1081.82tok/s]")
    }

    func test_strip_httpLine_leftUnchanged() {
        let raw = "127.0.0.1 - - [22/Mar/2026 10:09:03] \"POST /v1/chat/completions HTTP/1.1\" 200 -"
        let result = LogLineStripper.strip(raw, event: nil)
        XCTAssertTrue(result.hasPrefix("127.0.0.1"))
    }

    // MARK: - Truncation

    func test_strip_longLine_truncatedAt70() {
        let long = String(repeating: "a", count: 80)
        let result = LogLineStripper.strip(long, event: nil)
        XCTAssertEqual(result.count, 71) // 70 chars + "…"
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func test_strip_exactly70Chars_notTruncated() {
        let exact = String(repeating: "b", count: 70)
        let result = LogLineStripper.strip(exact, event: nil)
        XCTAssertEqual(result, exact)
        XCTAssertFalse(result.hasSuffix("…"))
    }

    func test_strip_multibyteChars_truncatedByCharacterCount() {
        // █ is a multi-byte character; truncation must use Character count not byte count
        let long = String(repeating: "█", count: 80)
        let result = LogLineStripper.strip(long, event: nil)
        XCTAssertEqual(result.count, 71) // 70 + "…"
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func test_strip_emptyString_returnsEmpty() {
        XCTAssertEqual(LogLineStripper.strip("", event: nil), "")
    }
}

final class LogLineStripperEventTests: XCTestCase {

    // MARK: - Progress event

    func test_strip_progressEvent_returnsCompactFraction() {
        let line = "2026-03-24 23:30:06,751 - INFO - Prompt processing progress: 4096/9829"
        let event = LogEvent.progress(current: 4096, total: 9829, percentage: 41.7)
        XCTAssertEqual(LogLineStripper.strip(line, event: event), "4096/9829")
    }

    // MARK: - KV cache event

    func test_strip_kvCachesEvent_returnsCompactGbAndTokens() {
        let line = "KV Caches: ... 1.54 GB, latest user cache 9826 tokens"
        let event = LogEvent.kvCaches(gpuGB: 1.54, tokens: 9826)
        XCTAssertEqual(LogLineStripper.strip(line, event: event), "1.54 GB · 9826 tok")
    }

    func test_strip_kvCachesEventZero_formatsToTwoDecimalPlaces() {
        let line = "KV Caches: ... 0.00 GB, latest user cache 0 tokens"
        let event = LogEvent.kvCaches(gpuGB: 0.0, tokens: 0)
        XCTAssertEqual(LogLineStripper.strip(line, event: event), "0.00 GB · 0 tok")
    }

    // MARK: - httpCompletion event (compact summary)

    func test_strip_httpCompletionEvent_returnsCompactSummary() {
        let line = "127.0.0.1 - - [24/Mar/2026 23:29:18] \"POST /v1/chat/completions HTTP/1.1\" 200 -"
        let result = LogLineStripper.strip(line, event: .httpCompletion)
        XCTAssertEqual(result, "POST /completions 200")
    }

    // MARK: - nil event (existing strip+truncate behaviour preserved)

    func test_strip_nilEvent_shortPlainLine_leftUnchanged() {
        XCTAssertEqual(LogLineStripper.strip("Server started", event: nil), "Server started")
    }

    func test_strip_nilEvent_timestampedLine_prefixStripped() {
        let line = "2026-03-24 23:29:18,794 - INFO - Server started"
        XCTAssertEqual(LogLineStripper.strip(line, event: nil), "Server started")
    }
}
