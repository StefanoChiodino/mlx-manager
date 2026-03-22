# Status Bar Log Line Streaming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream the last server log line into the menu bar status item (to the right of the arc/M icon), opt-in via a Settings checkbox.

**Architecture:** Add a pure `LogLineStripper` for prefix stripping and truncation. Pipe stripped lines from `AppDelegate.handleLogEvent` into `StatusBarView` via `StatusBarViewProtocol.updateLogLine`. Gate on `AppSettings.showLastLogLine`. Add a checkbox to SettingsWindowController alongside the existing `ramGraphCheckbox` pattern.

**Tech Stack:** Swift 5.9, AppKit, SPM, XCTest

---

## File Map

| File | Action |
|------|--------|
| `Sources/MLXManager/LogLineStripper.swift` | Create — pure stripping + truncation function |
| `Sources/MLXManager/AppSettings.swift` | Modify — add `showLastLogLine: Bool` |
| `Sources/MLXManager/StatusBarController.swift` | Modify — add `updateLogLine` to protocol + controller |
| `Sources/MLXManagerApp/StatusBarView.swift` | Modify — implement `updateLogLine` via `statusItem.button?.title` |
| `Sources/MLXManagerApp/AppDelegate.swift` | Modify — call `updateLogLine` in `handleLogEvent` and `resetSession` |
| `Sources/MLXManagerApp/SettingsWindowController.swift` | Modify — add `showLastLogLineCheckbox` |
| `Tests/MLXManagerTests/LogLineStripperTests.swift` | Create — full coverage of strip rules and truncation |
| `Tests/MLXManagerTests/AppSettingsTests.swift` | Modify — add tests for `showLastLogLine` |
| `Tests/MLXManagerTests/StatusBarControllerTests.swift` | Modify — add `updateLogLine` forwarding test to mock |

---

### Task 1: `LogLineStripper` — pure stripping function

**Files:**
- Create: `Sources/MLXManager/LogLineStripper.swift`
- Create: `Tests/MLXManagerTests/LogLineStripperTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MLXManagerTests/LogLineStripperTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to confirm they fail**

```bash
swift test --filter LogLineStripperTests 2>&1 | tail -20
```
Expected: compile error — `LogLineStripper` not found.

- [ ] **Step 3: Create `LogLineStripper.swift`**

Create `Sources/MLXManager/LogLineStripper.swift`:

```swift
import Foundation

/// Strips known log prefixes and truncates lines for display in the menu bar.
public enum LogLineStripper {

    private static let maxLength = 70

    /// Strip known prefixes from `line`, then truncate to 70 Swift Characters.
    /// Rules applied in order (first match wins):
    ///   1. `YYYY-MM-DD HH:MM:SS,mmm - INFO - ` (mlx_lm.server format)
    ///   2. `INFO: ` followed by one or more spaces (uvicorn/vision format)
    /// Lines matching no rule are returned as-is (before truncation).
    public static func strip(_ line: String) -> String {
        let stripped = stripped(line)
        return truncated(stripped)
    }

    private static func stripped(_ line: String) -> String {
        // Rule 1: datetime INFO prefix
        // Pattern: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d+ - INFO -
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

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter LogLineStripperTests 2>&1 | tail -20
```
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MLXManager/LogLineStripper.swift Tests/MLXManagerTests/LogLineStripperTests.swift
git commit -m "feat: add LogLineStripper for status bar log line display"
```

---

### Task 2: `AppSettings` — add `showLastLogLine`

**Files:**
- Modify: `Sources/MLXManager/AppSettings.swift`
- Modify: `Tests/MLXManagerTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/MLXManagerTests/AppSettingsTests.swift`:

```swift
func test_appSettings_showLastLogLine_defaultsFalse() {
    XCTAssertEqual(AppSettings().showLastLogLine, false)
}

func test_appSettings_showLastLogLine_roundTripsJSON() throws {
    var s = AppSettings()
    s.showLastLogLine = true
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded.showLastLogLine, true)
}

func test_appSettings_showLastLogLine_migratesFromOldJSON() throws {
    // Old JSON without the field should default to false
    let oldData = Data("""
    {
      "ramGraphEnabled": false,
      "ramPollInterval": 5,
      "startAtLogin": false,
      "logPath": "~/repos/mlx/Logs/server.log",
      "progressCompletionThreshold": 99
    }
    """.utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: oldData)
    XCTAssertEqual(decoded.showLastLogLine, false)
}
```

- [ ] **Step 2: Run to confirm they fail**

```bash
swift test --filter AppSettingsTests 2>&1 | tail -20
```
Expected: compile error — `showLastLogLine` not found on `AppSettings`.

- [ ] **Step 3: Add `showLastLogLine` to `AppSettings`**

In `Sources/MLXManager/AppSettings.swift`:

Add the property after `progressCompletionThreshold`:
```swift
public var showLastLogLine: Bool = false
```

Add to `CodingKeys`:
```swift
case showLastLogLine
```

Add to `init(from decoder:)` after `progressCompletionThreshold`:
```swift
showLastLogLine = try container.decodeIfPresent(Bool.self, forKey: .showLastLogLine) ?? false
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter AppSettingsTests 2>&1 | tail -20
```
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MLXManager/AppSettings.swift Tests/MLXManagerTests/AppSettingsTests.swift
git commit -m "feat: add showLastLogLine setting to AppSettings"
```

---

### Task 3: `StatusBarViewProtocol` + `StatusBarController` — add `updateLogLine`

**Files:**
- Modify: `Sources/MLXManager/StatusBarController.swift`
- Modify: `Tests/MLXManagerTests/StatusBarControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MLXManagerTests/StatusBarControllerTests.swift` (inside the `StatusBarControllerTests` suite):

```swift
@Test("updateLogLine forwards to view")
func updateLogLineForwardsToView() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    controller.updateLogLine("processing: 4096/24378")
    #expect(view.lastLogLine == "processing: 4096/24378")
}

@Test("updateLogLine nil clears view")
func updateLogLineNilClearsView() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    controller.updateLogLine("some line")
    controller.updateLogLine(nil)
    #expect(view.lastLogLine == nil)
}
```

Also add `lastLogLine` to `MockStatusBarView` and `updateLogLine` to its `StatusBarViewProtocol` conformance:

```swift
var lastLogLine: String?

func updateLogLine(_ line: String?) {
    lastLogLine = line
}
```

- [ ] **Step 2: Run to confirm they fail**

```bash
swift test --filter StatusBarControllerTests 2>&1 | tail -20
```
Expected: compile error — `updateLogLine` not found.

- [ ] **Step 3: Add to protocol and controller**

In `Sources/MLXManager/StatusBarController.swift`, add to `StatusBarViewProtocol`:
```swift
func updateLogLine(_ line: String?)
```

Add to `StatusBarController`:
```swift
public func updateLogLine(_ line: String?) {
    view.updateLogLine(line)
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter StatusBarControllerTests 2>&1 | tail -20
```
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MLXManager/StatusBarController.swift Tests/MLXManagerTests/StatusBarControllerTests.swift
git commit -m "feat: add updateLogLine to StatusBarViewProtocol and StatusBarController"
```

---

### Task 4: `StatusBarView` — implement `updateLogLine` (no TDD — AppKit)

**Files:**
- Modify: `Sources/MLXManagerApp/StatusBarView.swift`

- [ ] **Step 1: Add `updateLogLine` to `StatusBarView`**

In `Sources/MLXManagerApp/StatusBarView.swift`, add after `showLogView`:

```swift
func updateLogLine(_ line: String?) {
    DispatchQueue.main.async { [weak self] in
        self?.statusItem.button?.title = line.map { " \($0)" } ?? ""
    }
}
```

(The leading space creates visual separation between the arc view and the text.)

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -10
```
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/MLXManagerApp/StatusBarView.swift
git commit -m "feat: implement updateLogLine in StatusBarView via statusItem title"
```

---

### Task 5: `AppDelegate` — wire log line streaming

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

No TDD — AppKit wiring. Build verification only.

- [ ] **Step 1: Add `updateLogLine` call in `handleLogEvent`**

In `Sources/MLXManagerApp/AppDelegate.swift`, inside `handleLogEvent(_ event:)`, after the `logLines.append` block, add:

```swift
if settings.showLastLogLine {
    let stripped = LogLineStripper.strip(line) // `line` is already in scope from rawLine(for: event)
    statusBarController.updateLogLine(stripped)
}
```

- [ ] **Step 2: Add clear in `resetSession`**

In `resetSession()`, add after `logLines = []`:

```swift
statusBarController.updateLogLine(nil)
```

- [ ] **Step 3: Verify build and all tests pass**

```bash
swift build 2>&1 | tail -10 && swift test 2>&1 | tail -20
```
Expected: Build succeeds. All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "feat: wire log line streaming in AppDelegate"
```

---

### Task 6: `SettingsWindowController` — add checkbox (no TDD — AppKit)

**Files:**
- Modify: `Sources/MLXManagerApp/SettingsWindowController.swift`

Follow the existing `ramGraphCheckbox` pattern exactly.

- [ ] **Step 1: Add the checkbox property**

Near the top of the class, after `startAtLoginCheckbox`, add:

```swift
private let showLastLogLineCheckbox = NSButton(checkboxWithTitle: "Show last log line in menu bar", target: nil, action: nil)
```

- [ ] **Step 2: Wire the checkbox state in `loadGeneralSettings()`**

Find the section where `ramGraphCheckbox` and `startAtLoginCheckbox` are populated (around line 349). Add after `startAtLoginCheckbox`:

```swift
showLastLogLineCheckbox.state = draftSettings.showLastLogLine ? .on : .off
showLastLogLineCheckbox.target = self
showLastLogLineCheckbox.action = #selector(showLastLogLineToggled)
```

- [ ] **Step 3: Add to the general settings grid**

Find where `startAtLoginCheckbox` is added to the grid. Add the new checkbox as a new grid row in the same pattern. The grid rows follow the pattern:
```swift
grid.addRow(with: [NSGridCell.emptyContentView, showLastLogLineCheckbox])
```

- [ ] **Step 4: Add the toggle action**

Add a new `@objc` method alongside `ramGraphToggled`:

```swift
@objc private func showLastLogLineToggled() {
    draftSettings.showLastLogLine = showLastLogLineCheckbox.state == .on
}
```

- [ ] **Step 5: Persist in `saveTapped`**

Find where `draftSettings.ramGraphEnabled` and `draftSettings.startAtLogin` are saved in `saveTapped`. Add:

```swift
draftSettings.showLastLogLine = showLastLogLineCheckbox.state == .on
```

- [ ] **Step 6: Verify build**

```bash
swift build 2>&1 | tail -10
```
Expected: Build succeeds.

- [ ] **Step 7: Run all tests**

```bash
swift test 2>&1 | tail -20
```
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/MLXManagerApp/SettingsWindowController.swift
git commit -m "feat: add show last log line checkbox to Settings"
```

---

### Task 7: Manual Verification

- [ ] **Step 1: Build and install**

```bash
make install
```

- [ ] **Step 2: Verify off by default**

Open Settings → confirm "Show last log line in menu bar" is unchecked. Status bar shows only the arc icon.

- [ ] **Step 3: Enable and verify**

Check the box, click Save. Start the server. Confirm the last log line appears to the right of the arc icon in the menu bar, updating as new log lines arrive.

- [ ] **Step 4: Verify clearing**

Stop the server. Confirm the log text disappears from the menu bar.

- [ ] **Step 5: Verify stripping**

While the server is running, confirm the status bar text does NOT show the `2026-03-22 10:09:07,338 - INFO -` prefix — only the content after it.
