# Log Filtering & Status Bar Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the KV cache regex to match the new log format, and make the status bar label show compact formatted strings for progress and KV cache events instead of raw log lines.

**Architecture:** Two focused changes: (1) fix `LogParser.kvCachesRE` to drop the `\d+ seq,` requirement, and (2) update `LogLineStripper.strip` to accept an optional `LogEvent` and format it compactly. `AppDelegate` passes the event it already has into the updated stripper. Show logs popover is untouched.

**Tech Stack:** Swift, XCTest, `NSRegularExpression`, `String(format:)`

---

## File Map

| File | Change |
| ---- | ------ |
| `Sources/MLXManager/LogParser.swift` | Update `kvCachesRE` pattern |
| `Sources/MLXManager/LogLineStripper.swift` | Add `event: LogEvent?` param; format progress/kvCaches compactly |
| `Sources/MLXManagerApp/AppDelegate.swift` | Pass `event` to `LogLineStripper.strip` |
| `Tests/MLXManagerTests/LogParserTests.swift` | Add new-format KV cache test cases |
| `Tests/MLXManagerTests/LogLineStripperTests.swift` | Update existing calls to new signature; add event-aware test cases |

---

## Task 1: Fix `LogParser.kvCachesRE` — RED

**Files:**
- Modify: `Tests/MLXManagerTests/LogParserTests.swift`

The new log format omits `\d+ seq,` and uses `...` instead. The existing regex doesn't match it. Write failing tests first.

- [ ] **Step 1: Add failing tests for new KV cache format**

In `Tests/MLXManagerTests/LogParserTests.swift`, add inside `final class LogParserTests`:

```swift
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
```

- [ ] **Step 2: Run the new tests to confirm they FAIL**

```bash
cd /Users/stefano/repos/mlx-manager
xcodebuild test -scheme MLXManager -destination 'platform=macOS' -only-testing 'MLXManagerTests/LogParserTests/test_parse_kvCachesNewFormat_returnsGpuAndTokens' -only-testing 'MLXManagerTests/LogParserTests/test_parse_kvCachesNewFormatZero_returnsZeroValues' 2>&1 | grep -E "FAIL|PASS|error:"
```

Expected: both FAIL — `Expected .kvCaches, got nil`

---

## Task 2: Fix `LogParser.kvCachesRE` — GREEN

**Files:**
- Modify: `Sources/MLXManager/LogParser.swift:30`

- [ ] **Step 3: Update the regex**

In `Sources/MLXManager/LogParser.swift`, change line 30–32 from:

```swift
private static let kvCachesRE = try! NSRegularExpression(
    pattern: #"KV Caches:\s*\d+\s+seq,\s*([\d.]+)\s+GB,.*?(\d+)\s+tokens"#
)
```

to:

```swift
private static let kvCachesRE = try! NSRegularExpression(
    pattern: #"KV Caches:.*?([\d.]+)\s+GB,.*?(\d+)\s+tokens"#
)
```

- [ ] **Step 4: Run all LogParser tests to confirm they pass**

```bash
cd /Users/stefano/repos/mlx-manager
xcodebuild test -scheme MLXManager -destination 'platform=macOS' -only-testing 'MLXManagerTests/LogParserTests' 2>&1 | grep -E "FAIL|PASS|error:|Test Suite"
```

Expected: all PASS (new tests + existing regression tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/MLXManager/LogParser.swift Tests/MLXManagerTests/LogParserTests.swift
git commit -m "fix: update kvCachesRE to match new log format without seq count"
```

---

## Task 3: Update `LogLineStripper` signature — RED

**Files:**
- Modify: `Tests/MLXManagerTests/LogLineStripperTests.swift`

The existing tests call `LogLineStripper.strip(raw)` with one argument. After the signature change those will fail to compile. We write the new tests first, then update the old calls as part of making everything compile.

- [ ] **Step 6: Add new event-aware test cases**

In `Tests/MLXManagerTests/LogLineStripperTests.swift`, add a new test class after the closing `}` of `LogLineStripperTests`:

```swift
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

    // MARK: - httpCompletion event (fallthrough to strip+truncate)

    func test_strip_httpCompletionEvent_truncatesLongRawLine() {
        // 79-char line, no strippable prefix → truncated at 70 + "…" = 71 chars
        let line = "127.0.0.1 - - [24/Mar/2026 23:29:18] \"POST /v1/chat/completions HTTP/1.1\" 200 -"
        let event = LogEvent.httpCompletion
        let result = LogLineStripper.strip(line, event: event)
        XCTAssertEqual(result.count, 71)
        XCTAssertTrue(result.hasSuffix("…"))
        XCTAssertTrue(result.hasPrefix("127.0.0.1"))
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
```

- [ ] **Step 7: Run tests to confirm compilation failure (signature not yet changed)**

```bash
cd /Users/stefano/repos/mlx-manager
xcodebuild test -scheme MLXManager -destination 'platform=macOS' -only-testing 'MLXManagerTests/LogLineStripperEventTests' 2>&1 | grep -E "error:|FAIL|PASS"
```

Expected: compile error — `extra argument 'event' in call` (or similar). This confirms the tests are driving the implementation.

---

## Task 4: Update `LogLineStripper` — GREEN

**Files:**
- Modify: `Sources/MLXManager/LogLineStripper.swift`
- Modify: `Tests/MLXManagerTests/LogLineStripperTests.swift` (update old calls)

- [ ] **Step 8: Update `LogLineStripper.swift`**

Replace the entire contents of `Sources/MLXManager/LogLineStripper.swift`:

```swift
import Foundation

/// Strips known log prefixes and formats lines for display in the menu bar.
///
/// - For `.progress` and `.kvCaches` events, returns a compact formatted string.
/// - For all other events (including `nil`), strips the timestamp prefix and truncates to 70 characters.
public enum LogLineStripper {

    private static let maxLength = 70

    /// Returns a compact string suitable for display in the status bar.
    ///
    /// - Parameters:
    ///   - line: The raw log line.
    ///   - event: The parsed event for this line, if any.
    public static func strip(_ line: String, event: LogEvent?) -> String {
        switch event {
        case .progress(let current, let total, _):
            return "\(current)/\(total)"
        case .kvCaches(let gpuGB, let tokens):
            return "\(String(format: "%.2f", gpuGB)) GB · \(tokens) tok"
        default:
            return truncated(stripped(line))
        }
    }

    private static func stripped(_ line: String) -> String {
        // Rule 1: datetime INFO prefix
        if let range = line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d+ - INFO - "#,
                                   options: .regularExpression) {
            return String(line[range.upperBound...])
        }
        // Rule 2: INFO: followed by one or more spaces
        if let range = line.range(of: #"^INFO:\s+"#, options: .regularExpression) {
            return String(line[range.upperBound...])
        }
        return line
    }

    private static func truncated(_ s: String) -> String {
        guard s.count > maxLength else { return s }
        let end = s.index(s.startIndex, offsetBy: maxLength)
        return String(s[..<end]) + "…"
    }
}
```

- [ ] **Step 9: Update existing `LogLineStripperTests` to use new signature**

In `Tests/MLXManagerTests/LogLineStripperTests.swift`, update every call from `LogLineStripper.strip(raw)` / `LogLineStripper.strip(long)` / `LogLineStripper.strip(exact)` / `LogLineStripper.strip("")` to pass `event: nil`. There are exactly 10 calls across the existing tests. Change each one:

```swift
// Before:
LogLineStripper.strip(raw)
// After:
LogLineStripper.strip(raw, event: nil)
```

All 10 locations to update (one per test method call site):
- `test_strip_removesDatetimeInfoPrefix` — `LogLineStripper.strip(raw)` → `LogLineStripper.strip(raw, event: nil)`
- `test_strip_removesDatetimeInfoPrefix_differentTimestamp` — same pattern
- `test_strip_removesUvicornInfoPrefix` — same pattern
- `test_strip_removesUvicornInfoPrefix_singleSpace` — same pattern
- `test_strip_noPrefix_leftUnchanged` — same pattern
- `test_strip_httpLine_leftUnchanged` — same pattern
- `test_strip_longLine_truncatedAt70` — `LogLineStripper.strip(long)` → `LogLineStripper.strip(long, event: nil)`
- `test_strip_exactly70Chars_notTruncated` — `LogLineStripper.strip(exact)` → `LogLineStripper.strip(exact, event: nil)`
- `test_strip_multibyteChars_truncatedByCharacterCount` — `LogLineStripper.strip(long)` → `LogLineStripper.strip(long, event: nil)`
- `test_strip_emptyString_returnsEmpty` — `LogLineStripper.strip("")` → `LogLineStripper.strip("", event: nil)`

- [ ] **Step 10: Run all LogLineStripper tests to confirm they pass**

```bash
cd /Users/stefano/repos/mlx-manager
xcodebuild test -scheme MLXManager -destination 'platform=macOS' -only-testing 'MLXManagerTests/LogLineStripperTests' -only-testing 'MLXManagerTests/LogLineStripperEventTests' 2>&1 | grep -E "FAIL|PASS|error:|Test Suite"
```

Expected: all PASS

- [ ] **Step 11: Commit**

```bash
git add Sources/MLXManager/LogLineStripper.swift Tests/MLXManagerTests/LogLineStripperTests.swift
git commit -m "feat: format progress and kvCaches compactly in status bar label"
```

---

## Task 5: Update `AppDelegate` call site

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift:66`

- [ ] **Step 12: Update the call site**

In `Sources/MLXManagerApp/AppDelegate.swift`, find (around line 66):

```swift
self.statusBarController.updateLogLine(LogLineStripper.strip(line))
```

Change to:

```swift
self.statusBarController.updateLogLine(LogLineStripper.strip(line, event: event))
```

- [ ] **Step 13: Build to confirm no compile errors**

```bash
cd /Users/stefano/repos/mlx-manager
xcodebuild build -scheme MLXManager -destination 'platform=macOS' 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 14: Run the full test suite**

```bash
cd /Users/stefano/repos/mlx-manager
xcodebuild test -scheme MLXManager -destination 'platform=macOS' 2>&1 | grep -E "FAIL|error:|Test Suite.*passed|Test Suite.*failed"
```

Expected: all test suites pass, no failures.

- [ ] **Step 15: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "fix: pass event to LogLineStripper for compact status bar display"
```
