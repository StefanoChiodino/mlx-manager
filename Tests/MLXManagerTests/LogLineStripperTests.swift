import XCTest
@testable import MLXManager

final class LogLineStripperTests: XCTestCase {

    // MARK: - mlx_lm.server prefix (datetime + INFO)

    func test_strip_removesDatetimeInfoPrefix() {
        let raw = "2026-03-22 10:09:07,338 - INFO - Prompt processing progress: 4096/24378"
        let result = LogLineStripper.strip(raw)
        XCTAssertEqual(result, "Prompt processing progress: 4096/24378")
    }

    func test_strip_removesDatetimeInfoPrefix_differentTimestamp() {
        let raw = "2026-01-01 00:00:00,000 - INFO - KV Caches: 0 seq, 0.00 GB"
        let result = LogLineStripper.strip(raw)
        XCTAssertEqual(result, "KV Caches: 0 seq, 0.00 GB")
    }

    // MARK: - Vision/uvicorn prefix (INFO:     )

    func test_strip_removesUvicornInfoPrefix() {
        let raw = "INFO:     Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)"
        let result = LogLineStripper.strip(raw)
        XCTAssertEqual(result, "Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)")
    }

    func test_strip_removesUvicornInfoPrefix_singleSpace() {
        let raw = "INFO: Application startup complete."
        let result = LogLineStripper.strip(raw)
        XCTAssertEqual(result, "Application startup complete.")
    }

    // MARK: - No prefix — leave unchanged

    func test_strip_noPrefix_leftUnchanged() {
        let raw = "Prefill: 100%|█████████▉| 23214/23215 [00:21<00:00, 1081.82tok/s]"
        let result = LogLineStripper.strip(raw)
        XCTAssertEqual(result, "Prefill: 100%|█████████▉| 23214/23215 [00:21<00:00, 1081.82tok/s]")
    }

    func test_strip_httpLine_leftUnchanged() {
        let raw = "127.0.0.1 - - [22/Mar/2026 10:09:03] \"POST /v1/chat/completions HTTP/1.1\" 200 -"
        let result = LogLineStripper.strip(raw)
        XCTAssertTrue(result.hasPrefix("127.0.0.1"))
    }

    // MARK: - Truncation

    func test_strip_longLine_truncatedAt70() {
        let long = String(repeating: "a", count: 80)
        let result = LogLineStripper.strip(long)
        XCTAssertEqual(result.count, 71) // 70 chars + "…"
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func test_strip_exactly70Chars_notTruncated() {
        let exact = String(repeating: "b", count: 70)
        let result = LogLineStripper.strip(exact)
        XCTAssertEqual(result, exact)
        XCTAssertFalse(result.hasSuffix("…"))
    }

    func test_strip_multibyteChars_truncatedByCharacterCount() {
        // █ is a multi-byte character; truncation must use Character count not byte count
        let long = String(repeating: "█", count: 80)
        let result = LogLineStripper.strip(long)
        XCTAssertEqual(result.count, 71) // 70 + "…"
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func test_strip_emptyString_returnsEmpty() {
        XCTAssertEqual(LogLineStripper.strip(""), "")
    }
}
