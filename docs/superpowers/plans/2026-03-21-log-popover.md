# Log Popover + Historical Log Loading — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the log NSWindow with an NSPopover (matching RAM/history pattern), load last 100 log lines from disk on startup, and populate request history from those historical lines.

**Architecture:** Move `LogLineKind` to the MLXManager framework so it can be used in `StatusBarViewProtocol`. Add `showLogView` to the protocol/controller. AppDelegate maintains an in-memory `logLines` buffer populated from disk history + live tailing. A new `LogPopoverView` renders color-coded lines in an NSPopover. Historical log parsing uses a separate `ServerState` instance to extract `RequestRecord`s without corrupting live state.

**Tech Stack:** Swift 5.9, AppKit, SPM, XCTest + Swift Testing

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/MLXManager/LogParser.swift` | Modify | Add `LogLineKind` enum (moved from app target) |
| `Sources/MLXManager/StatusBarController.swift` | Modify | Add `showLogView(lines:)` to protocol + controller |
| `Sources/MLXManagerApp/LogPopoverView.swift` | Create | NSView with NSScrollView+NSTextView for popover log display |
| `Sources/MLXManagerApp/StatusBarView.swift` | Modify | Implement `showLogView` using NSPopover |
| `Sources/MLXManager/HistoricalLogLoader.swift` | Create | Pure function to parse last N lines from file content into `[(String, LogLineKind)]` + `[RequestRecord]` |
| `Sources/MLXManagerApp/AppDelegate.swift` | Modify | `logLines` buffer, call `HistoricalLogLoader`, wire popover, remove `logWindowController` |
| `Sources/MLXManagerApp/LogWindowController.swift` | Delete | Replaced by popover |
| `Tests/MLXManagerTests/StatusBarControllerTests.swift` | Modify | Update mock, add `showLogView` test |
| `Tests/MLXManagerTests/StatusBarControllerNewTests.swift` | Modify | Update mock reference |
| `Tests/MLXManagerTests/HistoricalLogLoaderTests.swift` | Create | Tests for historical log parsing |

---

### Task 1: Move `LogLineKind` to MLXManager Framework

**Files:**
- Modify: `Sources/MLXManager/LogParser.swift`
- Modify: `Sources/MLXManagerApp/LogWindowController.swift` (remove `LogLineKind` from here)

- [ ] **Step 1: Write the failing test**

Add a test in `Tests/MLXManagerTests/LogParserTests.swift` that verifies `LogLineKind` can be constructed from a `LogEvent`:

```swift
@Test("LogLineKind maps progress event")
func logLineKindMapsProgress() {
    let kind = LogLineKind(.progress(current: 1, total: 10, percentage: 10.0))
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LogParserTests/logLineKindMaps 2>&1 | tail -20`
Expected: FAIL — `LogLineKind` not found in MLXManager module.

- [ ] **Step 3: Write minimal implementation**

Add to `Sources/MLXManager/LogParser.swift`, after the `LogEvent` enum:

```swift
public enum LogLineKind: Equatable {
    case progress, kvCaches, httpCompletion, warning, other

    public init(_ event: LogEvent) {
        switch event {
        case .progress:       self = .progress
        case .kvCaches:       self = .kvCaches
        case .httpCompletion: self = .httpCompletion
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LogParserTests/logLineKindMaps 2>&1 | tail -20`
Expected: PASS (3 tests)

- [ ] **Step 5: Remove `LogLineKind` from `LogWindowController.swift`**

Delete lines 4-14 from `Sources/MLXManagerApp/LogWindowController.swift` (the `LogLineKind` enum definition). The app target imports `MLXManager`, so it will pick up the framework version.

- [ ] **Step 6: Verify full build**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/MLXManager/LogParser.swift Sources/MLXManagerApp/LogWindowController.swift Tests/MLXManagerTests/LogParserTests.swift
git commit -m "refactor: move LogLineKind to MLXManager framework"
```

---

### Task 2: Add `showLogView` to `StatusBarViewProtocol` and `StatusBarController`

**Files:**
- Modify: `Sources/MLXManager/StatusBarController.swift`
- Modify: `Tests/MLXManagerTests/StatusBarControllerTests.swift`
- Modify: `Tests/MLXManagerTests/StatusBarControllerNewTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MLXManagerTests/StatusBarControllerTests.swift`:

```swift
@Test("showLogView forwards lines to view")
func showLogViewForwardsToView() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    let lines: [(String, LogLineKind)] = [
        ("test line", .other),
        ("progress 1/10", .progress),
    ]
    controller.showLogView(lines: lines)
    #expect(view.logLines?.count == 2)
    #expect(view.logLines?[0].0 == "test line")
    #expect(view.logLines?[0].1 == .other)
}
```

- [ ] **Step 2: Update `MockStatusBarView`**

In `Tests/MLXManagerTests/StatusBarControllerTests.swift`, add to `MockStatusBarView`:

```swift
var logLines: [(String, LogLineKind)]?

func showLogView(lines: [(String, LogLineKind)]) {
    logLines = lines
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter StatusBarControllerTests/showLogViewForwardsToView 2>&1 | tail -20`
Expected: FAIL — `showLogView` does not exist on `StatusBarViewProtocol` or `StatusBarController`.

- [ ] **Step 4: Write minimal implementation**

In `Sources/MLXManager/StatusBarController.swift`:

Add to `StatusBarViewProtocol`:
```swift
func showLogView(lines: [(String, LogLineKind)])
```

Add to `StatusBarController`:
```swift
public func showLogView(lines: [(String, LogLineKind)]) {
    view.showLogView(lines: lines)
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter StatusBarControllerTests/showLogViewForwardsToView 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Fix `StatusBarControllerNewTests` mock**

The `MockStatusBarView` class is defined in `StatusBarControllerTests.swift` and used by both test files. Since we added `showLogView` to the protocol, the mock already satisfies both. But verify the other test file compiles:

Run: `swift test --filter StatusBarControllerNewTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MLXManager/StatusBarController.swift Tests/MLXManagerTests/StatusBarControllerTests.swift
git commit -m "feat: add showLogView to StatusBarViewProtocol and StatusBarController"
```

---

### Task 3: Create `LogPopoverView`

**Files:**
- Create: `Sources/MLXManagerApp/LogPopoverView.swift`

No TDD for this task — it's a pure AppKit view (untestable without the UI). Build verification only.

- [ ] **Step 1: Create `LogPopoverView.swift`**

```swift
import AppKit
import MLXManager

final class LogPopoverView: NSView {

    private let textView: NSTextView
    private let scrollView: NSScrollView

    init(lines: [(String, LogLineKind)]) {
        scrollView = NSScrollView()
        textView = NSTextView()
        super.init(frame: NSRect(x: 0, y: 0, width: 500, height: 400))

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        renderLines(lines)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func renderLines(_ lines: [(String, LogLineKind)]) {
        let storage = textView.textStorage!
        for (line, kind) in lines {
            let colour: NSColor
            switch kind {
            case .progress:       colour = NSColor.labelColor
            case .kvCaches:       colour = NSColor.systemBlue
            case .httpCompletion: colour = NSColor.systemGreen
            case .warning:        colour = NSColor.systemOrange
            case .other:          colour = NSColor.labelColor
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: colour,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ]
            storage.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }
        // Scroll to bottom
        textView.scrollToEndOfDocument(nil)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/MLXManagerApp/LogPopoverView.swift
git commit -m "feat: add LogPopoverView for popover-based log display"
```

---

### Task 4: Implement `showLogView` in `StatusBarView` and wire up `AppDelegate`

**Files:**
- Modify: `Sources/MLXManagerApp/StatusBarView.swift`
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`
- Delete: `Sources/MLXManagerApp/LogWindowController.swift`

No TDD — AppKit wiring. Build + manual verification.

- [ ] **Step 1: Add `showLogView` to `StatusBarView`**

In `Sources/MLXManagerApp/StatusBarView.swift`, add after `closeHistoryView()`:

```swift
func showLogView(lines: [(String, LogLineKind)]) {
    let popover = NSPopover()
    popover.contentSize = NSSize(width: 500, height: 400)
    popover.behavior = .transient

    let viewController = NSViewController()
    let logView = LogPopoverView(lines: lines)
    logView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
    viewController.view = logView

    popover.contentViewController = viewController
    popover.show(relativeTo: statusItem.button?.bounds ?? .zero,
                 of: statusItem.button ?? NSView(),
                 preferredEdge: .minY)
}
```

- [ ] **Step 2: Update `AppDelegate` — add `logLines` buffer**

In `Sources/MLXManagerApp/AppDelegate.swift`:

Replace:
```swift
    // Windows
    private var logWindowController: LogWindowController?
```
With:
```swift
    // Log buffer
    private var logLines: [(String, LogLineKind)] = []
```

- [ ] **Step 3: Update `AppDelegate.showLog()`**

Replace the `showLog()` method:
```swift
private func showLog() {
    statusBarController.showLogView(lines: logLines)
}
```

- [ ] **Step 4: Update `AppDelegate.handleLogEvent()` — append to `logLines`**

Replace `logWindowController?.append(line: line, kind: kind)` with:
```swift
logLines.append((line, kind))
if logLines.count > 10_000 { logLines.removeFirst() }
```

- [ ] **Step 5: Update `AppDelegate.resetSession()`**

Replace `logWindowController?.clear()` with:
```swift
logLines = []
```

- [ ] **Step 6: Delete `LogWindowController.swift`**

```bash
rm Sources/MLXManagerApp/LogWindowController.swift
```

- [ ] **Step 7: Verify build**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 8: Run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 9: Commit**

```bash
git rm Sources/MLXManagerApp/LogWindowController.swift
git add Sources/MLXManagerApp/StatusBarView.swift Sources/MLXManagerApp/AppDelegate.swift
git commit -m "feat: replace log window with popover, add logLines buffer"
```

---

### Task 5: Load Historical Log Lines From Disk

**Files:**
- Create: `Sources/MLXManager/HistoricalLogLoader.swift`
- Create: `Tests/MLXManagerTests/HistoricalLogLoaderTests.swift`
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MLXManagerTests/HistoricalLogLoaderTests.swift`:

```swift
import Testing
@testable import MLXManager

@Suite("HistoricalLogLoader")
struct HistoricalLogLoaderTests {

    @Test("parses last N lines from file content")
    func parsesLastNLines() {
        let content = """
        some irrelevant line
        Prompt processing progress: 5/10
        KV Caches: 1 seq, 2.50 GB, latest user cache 100 tokens
        POST /v1/chat/completions HTTP/1.1" 200
        another irrelevant line
        """
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        #expect(result.lines.count == 5)
        #expect(result.lines[0].1 == .other)
        #expect(result.lines[1].1 == .progress)
        #expect(result.lines[2].1 == .kvCaches)
        #expect(result.lines[3].1 == .httpCompletion)
        #expect(result.lines[4].1 == .other)
    }

    @Test("extracts request records from complete sequences")
    func extractsRequestRecords() {
        let content = """
        Prompt processing progress: 5/10
        KV Caches: 1 seq, 2.50 GB, latest user cache 100 tokens
        """
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        #expect(result.records.count == 1)
        #expect(result.records[0].tokens == 100)
    }

    @Test("limits to last N lines")
    func limitsToLastNLines() {
        let lines = (1...200).map { "line \($0)" }
        let content = lines.joined(separator: "\n")
        let result = HistoricalLogLoader.load(from: content, maxLines: 50)
        #expect(result.lines.count == 50)
        #expect(result.lines[0].0 == "line 151")
    }

    @Test("incomplete request sequence produces no records")
    func incompleteSequenceNoRecords() {
        let content = "KV Caches: 1 seq, 2.50 GB, latest user cache 100 tokens"
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        #expect(result.records.isEmpty)
    }

    @Test("empty content returns empty results")
    func emptyContent() {
        let result = HistoricalLogLoader.load(from: "", maxLines: 100)
        #expect(result.lines.isEmpty)
        #expect(result.records.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HistoricalLogLoaderTests 2>&1 | tail -20`
Expected: FAIL — `HistoricalLogLoader` not found.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/MLXManager/HistoricalLogLoader.swift`:

```swift
import Foundation

public struct HistoricalLogResult {
    public let lines: [(String, LogLineKind)]
    public let records: [RequestRecord]
}

public enum HistoricalLogLoader {

    public static func load(from content: String, maxLines: Int) -> HistoricalLogResult {
        let allLines = content.components(separatedBy: "\n")
        let tail = allLines.suffix(maxLines)

        var lines: [(String, LogLineKind)] = []
        var records: [RequestRecord] = []
        var state = ServerState()
        state.serverStarted()

        for line in tail where !line.isEmpty {
            if let event = LogParser.parse(line: line) {
                lines.append((line, LogLineKind(event)))
                state.handle(event)
                if let record = state.completedRequest {
                    records.append(record)
                    state.clearCompletedRequest()
                }
            } else {
                lines.append((line, .other))
            }
        }

        return HistoricalLogResult(lines: lines, records: records)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HistoricalLogLoaderTests 2>&1 | tail -20`
Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MLXManager/HistoricalLogLoader.swift Tests/MLXManagerTests/HistoricalLogLoaderTests.swift
git commit -m "feat: add HistoricalLogLoader for parsing log history from disk"
```

- [ ] **Step 6: Wire `HistoricalLogLoader` into `AppDelegate`**

In `Sources/MLXManagerApp/AppDelegate.swift`, add a `loadHistoricalLog()` method after `startTailing()`:

```swift
private func loadHistoricalLog() {
    let path = logPath
    guard let data = FileManager.default.contents(atPath: path),
          let content = String(data: data, encoding: .utf8) else { return }
    let result = HistoricalLogLoader.load(from: content, maxLines: 100)
    logLines.append(contentsOf: result.lines)
    requestHistory.append(contentsOf: result.records)
}
```

Then add `loadHistoricalLog()` as the first line of `startTailing()`:

```swift
private func startTailing() {
    loadHistoricalLog()
    logTailer?.stop()
    // ... rest unchanged
```

- [ ] **Step 7: Verify build and tests**

Run: `swift build 2>&1 | tail -10 && swift test 2>&1 | tail -20`
Expected: Build succeeds. All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "feat: load last 100 log lines from disk on startup"
```

---

### Task 6: Manual Verification

- [ ] **Step 1: Build and install**

Run: `make install`

- [ ] **Step 2: Verify log popover**

1. Click the menu bar icon → "Show Log"
2. Confirm popover appears attached to the status bar (not a background window)
3. Confirm it contains historical log lines (not empty)
4. Confirm scrolling works
5. Click outside the popover — confirm it dismisses

- [ ] **Step 3: Verify request history**

1. Click "Request History"
2. Confirm bars appear for requests found in the historical log lines

- [ ] **Step 4: Verify live tailing**

1. Make a request to the server
2. Reopen "Show Log" — confirm the new log lines appear alongside the historical ones
