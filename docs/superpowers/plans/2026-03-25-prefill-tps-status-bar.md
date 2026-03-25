# Prefill Tok/s in Status Bar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display prefill speed (tok/s) in the menu bar as a dedicated label between the log line label and the arc icon, toggled by a new General settings checkbox.

**Architecture:** Add `timestamp: Date` to `LogEvent.progress` so `ServerState` can measure elapsed time between consecutive progress lines. `ServerState` accumulates progress events and computes `prefillTPS` when ≥2 consecutive lines arrive (no interruption, elapsed ≥ 0.1s). The result flows into `RequestRecord.prefillTPS`, is picked up by `StatusBarController`, and displayed via a new `tpsLabel` in `StatusBarView`.

**Tech Stack:** Swift, XCTest + Swift Testing, AppKit (NSTextField layout constraints), NSRegularExpression

---

## File Map

| File | Change |
|---|---|
| `Sources/MLXManager/LogParser.swift` | Add `timestamp: Date` to `LogEvent.progress`; parse timestamp from log line prefix; update `rawLine` reconstruction |
| `Sources/MLXManager/ServerCoordinator.swift` | Update `rawLine(for:)` switch arm for `.progress` |
| `Sources/MLXManager/ServerState.swift` | Add 5 accumulator fields; compute `pendingPrefillTPS` on batch completion; reset on stop/crash |
| `Sources/MLXManager/RequestRecord.swift` | Add `prefillTPS: Double?` property |
| `Sources/MLXManager/StatusBarController.swift` | Add `lastPrefillTPS: Double?`; update in `update(state:)`; clear on stop/failed; call `view.updateTPS(_:)`; add `updateTPS` to protocol |
| `Sources/MLXManager/AppSettings.swift` | Add `showPrefillTPS: Bool`; `CodingKeys` case; `decodeIfPresent` |
| `Sources/MLXManagerApp/StatusBarView.swift` | Add `tpsLabel: NSTextField`; layout between `logLabel` and `arcView`; implement `updateTPS(_:)` |
| `Sources/MLXManagerApp/SettingsWindowController.swift` | Add "Show prefill speed (tok/s)" checkbox after "Show last log line" |
| `Tests/MLXManagerTests/LogParserTests.swift` | Update all `.progress` constructions to pass `timestamp:`; add timestamp parsing tests |
| `Tests/MLXManagerTests/ServerStateTests.swift` | Update all `.progress` constructions; add prefill TPS accumulator tests |

---

## Task 1: Refactor — add `timestamp` to `LogEvent.progress` (green → green)

This is a **refactor step only**. No new behaviour. All existing tests must remain green throughout.

**Files:**
- Modify: `Sources/MLXManager/LogParser.swift`
- Modify: `Sources/MLXManager/ServerCoordinator.swift:104-113`
- Modify: `Tests/MLXManagerTests/LogParserTests.swift:165-183`
- Modify: `Tests/MLXManagerTests/StatusBarControllerTests.swift:507,545`

- [ ] **Step 1: Add `timestamp: Date` to `LogEvent.progress` with a placeholder parse site**

In `Sources/MLXManager/LogParser.swift`, update the enum case and parse site. Use `Date()` (wall clock) as a **temporary placeholder** — the real timestamp parsing comes in Task 2.

```swift
// Replace LogEvent enum (lines 4-8):
public enum LogEvent: Equatable {
    case progress(current: Int, total: Int, percentage: Double, timestamp: Date)
    case kvCaches(gpuGB: Double, tokens: Int)
    case httpCompletion
}
```

Update the progress parse site return (lines 47-51) to pass `Date()` temporarily:

```swift
return .progress(
    current: current,
    total: total,
    percentage: (Double(current) / Double(total)) * 100,
    timestamp: Date()
)
```

- [ ] **Step 2: Update `LogLineKind.init` switch arm**

In `Sources/MLXManager/LogParser.swift` lines 13-19, the `.progress` case has no value binding so it compiles as-is. Verify it still compiles — no code change needed here, but confirm.

- [ ] **Step 3: Update `ServerState.handle` switch arm**

In `Sources/MLXManager/ServerState.swift` line 58, add `timestamp` binding:

```swift
// Replace line 58:
case let .progress(current, total, percentage, _):
```

- [ ] **Step 4: Update `ServerCoordinator.rawLine(for:)` switch arm**

In `Sources/MLXManager/ServerCoordinator.swift` line 106, add `_` for the new label:

```swift
// Replace line 106:
case let .progress(current, total, _, _):
```

- [ ] **Step 5: Update all existing `LogParserTests` that construct `.progress`**

In `Tests/MLXManagerTests/LogParserTests.swift`, update the three `@Test` functions at lines 167-183 that directly construct `.progress`:

```swift
// line 169 — was: .progress(current: 1, total: 10, percentage: 10.0)
let kind = LogLineKind(.progress(current: 1, total: 10, percentage: 10.0, timestamp: Date()))
```

Also update any `guard case .progress(let current, let total, let percentage) = result` pattern matches in the test class (lines 12-13, 26-27) to add `let timestamp`:

```swift
guard case .progress(let current, let total, let percentage, let timestamp) = result else {
```

And add `XCTAssertNotNil(timestamp)` to those two tests.

- [ ] **Step 5b: Update `StatusBarControllerTests.swift` `.progress` constructions**

Two sites need `timestamp: Date()` added:

- Line 507: `state.handle(.progress(current: 10, total: 100, percentage: 10.0))` → add `, timestamp: Date()`
- Line 545 (inside `makeState`): `state.handle(.progress(current: c, total: t, percentage: ..., timestamp: Date()))`

- [ ] **Step 6: Update all existing `ServerStateTests` that construct `.progress`**

In `Tests/MLXManagerTests/ServerStateTests.swift`, every call like `.progress(current: 4096, total: 41061, percentage: 9.97)` needs a `timestamp:` argument. Replace all with:

```swift
.progress(current: 4096, total: 41061, percentage: 9.97, timestamp: Date())
```

Use a fixed sentinel `Date()` — the exact value doesn't matter for existing tests.

- [ ] **Step 7: Run all tests — verify green**

```bash
cd /Users/stefano/repos/mlx-manager
swift test 2>&1
```

Expected: all existing tests pass, zero failures.

- [ ] **Step 8: Commit**

```bash
git add Sources/MLXManager/LogParser.swift \
        Sources/MLXManager/ServerCoordinator.swift \
        Sources/MLXManager/ServerState.swift \
        Tests/MLXManagerTests/LogParserTests.swift \
        Tests/MLXManagerTests/ServerStateTests.swift
git commit -m "refactor: add timestamp to LogEvent.progress — update all switch arms and tests"
```

---

## Task 2: Test + implement timestamp parsing in LogParser (RED → GREEN)

**Files:**
- Modify: `Tests/MLXManagerTests/LogParserTests.swift`
- Modify: `Sources/MLXManager/LogParser.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/MLXManagerTests/LogParserTests.swift` inside the `LogParserTests` class:

```swift
// MARK: - Timestamp parsing

/// Spec: Timestamp is parsed from the log line prefix including milliseconds
func test_parse_progressLine_returnsTimestamp() {
    let line = "2026-03-25 10:41:25,583 - INFO - Prompt processing progress: 4096/33242"
    guard case .progress(_, _, _, let timestamp) = LogParser.parse(line: line) else {
        XCTFail("Expected .progress event")
        return
    }
    let cal = Calendar.current
    let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: timestamp)
    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 3)
    XCTAssertEqual(components.day, 25)
    XCTAssertEqual(components.hour, 10)
    XCTAssertEqual(components.minute, 41)
    XCTAssertEqual(components.second, 25)
}

/// Spec: Line with unparseable timestamp returns nil
func test_parse_progressLine_badTimestamp_returnsNil() {
    let line = "BADTSTAMP - INFO - Prompt processing progress: 4096/33242"
    XCTAssertNil(LogParser.parse(line: line))
}
```

- [ ] **Step 2: Run tests — verify RED**

```bash
swift test --filter LogParserTests/test_parse_progressLine_returnsTimestamp 2>&1
swift test --filter LogParserTests/test_parse_progressLine_badTimestamp_returnsNil 2>&1
```

Expected: `test_parse_progressLine_returnsTimestamp` FAILS (timestamp is `Date()` wall clock, not the log-line value). `test_parse_progressLine_badTimestamp_returnsNil` also FAILS (currently returns a `.progress` event instead of `nil`).

- [ ] **Step 3: Implement timestamp parsing in `LogParser`**

In `Sources/MLXManager/LogParser.swift`, add a pre-compiled timestamp formatter alongside the existing regex constants (after line 35):

```swift
private static let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    f.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
    return f
}()
```

Replace the `timestamp: Date()` placeholder in the parse site with real parsing. The full updated progress parse block (lines 42-52):

```swift
if let m = progressRE.firstMatch(in: line, range: range),
   let r1 = Range(m.range(at: 1), in: line),
   let r2 = Range(m.range(at: 2), in: line),
   let current = Int(line[r1]),
   let total = Int(line[r2]),
   let timestamp = timestampFormatter.date(from: String(line.prefix(23))) {
    return .progress(
        current: current,
        total: total,
        percentage: (Double(current) / Double(total)) * 100,
        timestamp: timestamp
    )
}
```

- [ ] **Step 4: Run all tests — verify green**

```bash
swift test 2>&1
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MLXManager/LogParser.swift Tests/MLXManagerTests/LogParserTests.swift
git commit -m "feat: parse timestamp from progress log line prefix"
```

---

## Task 3: Add `prefillTPS` accumulator to `ServerState` (RED → GREEN)

**Files:**
- Modify: `Tests/MLXManagerTests/ServerStateTests.swift`
- Modify: `Sources/MLXManager/ServerState.swift`
- Modify: `Sources/MLXManager/RequestRecord.swift`

- [ ] **Step 1: Add `prefillTPS: Double?` to `RequestRecord`**

In `Sources/MLXManager/RequestRecord.swift`, add the property:

```swift
public struct RequestRecord: Equatable {
    public let startedAt: Date
    public let completedAt: Date
    public let tokens: Int
    public let prefillTPS: Double?        // ← add this

    public var duration: TimeInterval { completedAt.timeIntervalSince(startedAt) }

    public init(startedAt: Date, completedAt: Date, tokens: Int, prefillTPS: Double? = nil) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.tokens = tokens
        self.prefillTPS = prefillTPS
    }
}
```

- [ ] **Step 2: Write failing tests for the accumulator**

Add to `Tests/MLXManagerTests/ServerStateTests.swift`:

```swift
// MARK: - Prefill TPS accumulator

@Test("Two consecutive progress events produce prefillTPS in completed record")
func twoConsecutiveProgressLines_producesPrefillTPS() {
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    let t2 = t1.addingTimeInterval(1.0)   // 1 second apart
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t2))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    let tps = state.completedRequest?.prefillTPS
    #expect(tps != nil)
    // 2000 tokens / 1.0s = 2000 tok/s
    #expect(abs(tps! - 2000.0) < 1.0)
}

@Test("Single progress line produces nil prefillTPS")
func singleProgressLine_nilPrefillTPS() {
    var state = ServerState()
    state.serverStarted()
    state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
    #expect(state.completedRequest?.prefillTPS == nil)
}

@Test("Interrupted progress batch (non-progress event between) produces nil prefillTPS")
func interruptedProgressBatch_nilPrefillTPS() {
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    // interrupt: kvCaches fires before second progress line
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 1000))
    // drain first record
    state.clearCompletedRequest()
    // new request: second progress line
    let t2 = t1.addingTimeInterval(2.0)
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t2))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    #expect(state.completedRequest?.prefillTPS == nil)
}

@Test("Elapsed less than 0.1s does not update pendingPrefillTPS")
func tooShortElapsed_doesNotUpdatePrefillTPS() {
    var state = ServerState()
    state.serverStarted()
    let t = Date()
    // Two progress lines 0.05s apart — below threshold
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t.addingTimeInterval(0.05)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    // Should be nil (no prior qualifying batch)
    #expect(state.completedRequest?.prefillTPS == nil)
}

@Test("pendingPrefillTPS persists across non-qualifying request")
func pendingPrefillTPS_persistsAcrossNonQualifyingRequest() {
    var state = ServerState()
    state.serverStarted()
    // First request: qualifying (2 lines, 1s apart)
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    let firstTPS = state.completedRequest?.prefillTPS
    state.clearCompletedRequest()
    #expect(firstTPS != nil)

    // Second request: single progress line (non-qualifying)
    state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
    // prefillTPS should equal the first qualifying value (pendingPrefillTPS persisted)
    #expect(state.completedRequest?.prefillTPS == firstTPS)
}

@Test("Accumulator resets on serverStopped")
func accumulatorResetsOnServerStopped() {
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.serverStopped()
    state.serverStarted()
    // Single line after restart — should not use pre-stop timestamps
    state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
    #expect(state.completedRequest?.prefillTPS == nil)
}

@Test("Accumulator resets on serverCrashed")
func accumulatorResetsOnServerCrashed() {
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.serverCrashed()
    state.serverStarted()
    state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
    #expect(state.completedRequest?.prefillTPS == nil)
}
```

- [ ] **Step 3: Run tests — verify RED**

```bash
swift test --filter ServerStateTests 2>&1
```

Expected: new tests FAIL (prefillTPS always nil, accumulator fields don't exist yet).

- [ ] **Step 4: Implement accumulator in `ServerState`**

In `Sources/MLXManager/ServerState.swift`, add five private fields after line 28:

```swift
private var requestStartedAt: Date? = nil

// Prefill TPS accumulator
private var firstProgressAt: Date? = nil
private var lastProgressAt: Date? = nil
private var lastProgressTokens: Int = 0
private var progressCount: Int = 0
private var pendingPrefillTPS: Double? = nil
```

Update `serverStopped()` (lines 36-41) to reset all five accumulator fields:

```swift
public mutating func serverStopped() {
    status = .offline
    progress = nil
    requestStartedAt = nil
    completedRequest = nil
    firstProgressAt = nil
    lastProgressAt = nil
    lastProgressTokens = 0
    progressCount = 0
    pendingPrefillTPS = nil
}
```

Update `serverCrashed()` (lines 43-48) identically:

```swift
public mutating func serverCrashed() {
    status = .failed
    progress = nil
    requestStartedAt = nil
    completedRequest = nil
    firstProgressAt = nil
    lastProgressAt = nil
    lastProgressTokens = 0
    progressCount = 0
    pendingPrefillTPS = nil
}
```

Update the `.progress` case in `handle(_:)` (line 58) to accumulate:

```swift
case let .progress(current, total, percentage, timestamp):
    if requestStartedAt == nil {
        requestStartedAt = Date()
    }
    // Accumulate for prefill TPS
    if progressCount == 0 {
        firstProgressAt = timestamp
    }
    lastProgressAt = timestamp
    lastProgressTokens = current
    progressCount += 1

    status = .processing
    progress = ProgressInfo(current: current, total: total, percentage: percentage)
```

Update the non-progress cases to flush+reset the accumulator before their existing logic. Add a helper:

```swift
private mutating func flushPrefillAccumulator() {
    if progressCount >= 2,
       let first = firstProgressAt,
       let last = lastProgressAt {
        let elapsed = last.timeIntervalSince(first)
        if elapsed >= 0.1 {
            pendingPrefillTPS = Double(lastProgressTokens) / elapsed
        }
        // else: leave pendingPrefillTPS unchanged
    }
    firstProgressAt = nil
    lastProgressAt = nil
    lastProgressTokens = 0
    progressCount = 0
}
```

Call it at the top of the `.kvCaches` and `.httpCompletion` cases:

```swift
case let .kvCaches(gpu, tok):
    flushPrefillAccumulator()
    gpuGB = gpu
    tokens = tok
    if status == .processing {
        emitRecord(tokens: tok)
        status = .idle
        progress = nil
    }

case .httpCompletion:
    flushPrefillAccumulator()
    if status == .processing {
        emitRecord(tokens: tokens ?? 0)
        status = .idle
        progress = nil
    }
```

Update `emitRecord(tokens:)` to include `pendingPrefillTPS`:

```swift
private mutating func emitRecord(tokens: Int) {
    guard let start = requestStartedAt else { return }
    completedRequest = RequestRecord(
        startedAt: start,
        completedAt: Date(),
        tokens: tokens,
        prefillTPS: pendingPrefillTPS
    )
    requestStartedAt = nil
}
```

- [ ] **Step 5: Run tests — verify green**

```bash
swift test 2>&1
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MLXManager/RequestRecord.swift \
        Sources/MLXManager/ServerState.swift \
        Tests/MLXManagerTests/ServerStateTests.swift
git commit -m "feat: accumulate prefill TPS in ServerState and surface via RequestRecord"
```

---

## Task 4: Add `showPrefillTPS` to `AppSettings` (RED → GREEN)

**Files:**
- Modify: `Tests/MLXManagerTests/AppSettingsTests.swift` (or create if not present)
- Modify: `Sources/MLXManager/AppSettings.swift`

- [ ] **Step 1: Locate existing AppSettings tests**

```bash
find /Users/stefano/repos/mlx-manager/Tests -name "AppSettingsTests.swift"
```

If the file exists, open it. If not, the test goes in a new file `Tests/MLXManagerTests/AppSettingsTests.swift`.

- [ ] **Step 2: Write the failing tests**

Add to the AppSettings test file:

```swift
func test_appSettings_showPrefillTPS_defaultsFalse() {
    let settings = AppSettings()
    XCTAssertFalse(settings.showPrefillTPS)
}

func test_appSettings_showPrefillTPS_roundTripsJSON() throws {
    var settings = AppSettings()
    settings.showPrefillTPS = true
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertTrue(decoded.showPrefillTPS)
}

func test_appSettings_showPrefillTPS_missingKeyDefaultsFalse() throws {
    // Simulate an old settings file that doesn't have showPrefillTPS
    let json = """
    {"ramGraphEnabled":false,"ramPollInterval":5,"startAtLogin":false,
     "logPath":"~/repos/mlx/Logs/server.log","serverPort":8080,
     "managedGatewayPort":8080,"progressCompletionThreshold":0,
     "showLastLogLine":false,"managedGatewayEnabled":false,"pythonPathOverride":""}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
    XCTAssertFalse(decoded.showPrefillTPS)
}
```

- [ ] **Step 3: Run tests — verify RED**

```bash
swift test --filter AppSettingsTests 2>&1
```

Expected: FAIL — `showPrefillTPS` property does not exist.

- [ ] **Step 4: Implement in `AppSettings`**

In `Sources/MLXManager/AppSettings.swift`:

Add property after `pythonPathOverride` (line 20):
```swift
/// Show prefill speed (tok/s) in the menu bar status item. Default false.
public var showPrefillTPS: Bool = false
```

Add to `CodingKeys` enum (after `pythonPathOverride` case, line 34):
```swift
case showPrefillTPS
```

Add to `init(from decoder:)` (after `pythonPathOverride` line, line 48):
```swift
showPrefillTPS = try container.decodeIfPresent(Bool.self, forKey: .showPrefillTPS) ?? false
```

- [ ] **Step 5: Run tests — verify green**

```bash
swift test 2>&1
```

- [ ] **Step 6: Commit**

```bash
git add Sources/MLXManager/AppSettings.swift Tests/
git commit -m "feat: add showPrefillTPS setting to AppSettings"
```

---

## Task 5: Add `updateTPS` to `StatusBarViewProtocol` and `StatusBarController` (RED → GREEN)

**Files:**
- Modify: `Sources/MLXManager/StatusBarController.swift`
- Modify: `Tests/MLXManagerTests/StatusBarControllerTests.swift` (locate or create)

- [ ] **Step 1: Add `updateTPS` stub to `MockStatusBarView` and to the protocol**

Both changes must happen together before writing tests — otherwise any test referencing `MockStatusBarView` will fail to compile.

In `Tests/MLXManagerTests/StatusBarControllerTests.swift`, add to `MockStatusBarView` after `updateLogLine` (around line 46):

```swift
var lastTPSValue: Double?? = .none   // .none = never called, .some(nil) = called with nil
func updateTPS(_ tps: Double?) { lastTPSValue = .some(tps) }
```

In `Sources/MLXManager/StatusBarController.swift`, add to `StatusBarViewProtocol` after `updateLogLine` (line 27):

```swift
func updateTPS(_ tps: Double?)
```

- [ ] **Step 2: Add `lastPrefillTPS` stub property to `StatusBarController`**

The new tests reference `controller.lastPrefillTPS`. Without this property the test file won't compile at all — a compile error is not a valid RED. Add just the stub declaration (no logic yet) to `Sources/MLXManager/StatusBarController.swift` after `lastDisplayState` (line 39):

```swift
public private(set) var lastPrefillTPS: Double? = nil
```

- [ ] **Step 3: Run all tests — verify still green**

```bash
swift test 2>&1
```

Expected: all pass (stubs compile, no behaviour changed yet).

- [ ] **Step 4: Write failing tests**

`StatusBarControllerTests.swift` uses Swift Testing (`import Testing`, `@Suite struct`). All new tests must use `@Test func` and `#expect`/`#require` — NOT `XCTAssert`. Add inside `struct StatusBarControllerTests`:

```swift
// MARK: - Prefill TPS

@Test("Qualifying record updates lastPrefillTPS and calls updateTPS")
func update_qualifyingRecord_updatesLastPrefillTPS() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: AppSettings(), fileExists: { _ in true })
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    controller.update(state: state)
    #expect(controller.lastPrefillTPS != nil)
    if case .some(let tps) = view.lastTPSValue {
        #expect(abs((tps ?? 0) - 2000.0) < 1.0)
    } else {
        Issue.record("updateTPS was never called")
    }
}

@Test("Non-qualifying record leaves lastPrefillTPS unchanged")
func update_nonQualifyingRecord_doesNotChangePrefillTPS() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: AppSettings(), fileExists: { _ in true })
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    controller.update(state: state)
    let firstTPS = controller.lastPrefillTPS
    state.clearCompletedRequest()
    state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
    controller.update(state: state)
    #expect(controller.lastPrefillTPS == firstTPS)
}

@Test("serverDidStop clears lastPrefillTPS and calls updateTPS(nil)")
func serverDidStop_clearsLastPrefillTPS() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: AppSettings(), fileExists: { _ in true })
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    controller.update(state: state)
    #expect(controller.lastPrefillTPS != nil)
    controller.serverDidStop()
    #expect(controller.lastPrefillTPS == nil)
    if case .some(let tps) = view.lastTPSValue {
        #expect(tps == nil)
    } else {
        Issue.record("updateTPS was never called")
    }
}

@Test("Failed status clears lastPrefillTPS")
func update_failedStatus_clearsLastPrefillTPS() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: AppSettings(), fileExists: { _ in true })
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    controller.update(state: state)
    #expect(controller.lastPrefillTPS != nil)
    state.serverCrashed()
    controller.update(state: state)
    #expect(controller.lastPrefillTPS == nil)
}
```

- [ ] **Step 5: Run tests — verify RED**

```bash
swift test --filter StatusBarControllerTests 2>&1
```

Expected: new TPS tests FAIL at runtime — `lastPrefillTPS` is `nil` (stub has no update logic yet), assertions fail.

- [ ] **Step 6: Add update logic to `StatusBarController`**

The stub property was already added in Step 2. Now add the behaviour. Do NOT re-declare `lastPrefillTPS` — it already exists.

Update `update(state:)` — add at the **start** of the method, before the switch (line 93):

```swift
if let record = state.completedRequest, let tps = record.prefillTPS {
    lastPrefillTPS = tps
    view.updateTPS(tps)
}
```

Update `serverDidStop()` — add after `view.updateState(.offline)` (line 88):

```swift
lastPrefillTPS = nil
view.updateTPS(nil)
```

Update the `.offline` and `.failed` cases in `update(state:)` switch — add `lastPrefillTPS = nil; view.updateTPS(nil)` to each:

```swift
case .offline:
    runningServer = nil
    lastDisplayState = .offline
    lastPrefillTPS = nil
    view.updateTPS(nil)
    view.updateState(.offline)
    rebuildMenu(statusText: "Server: Offline")

case .failed:
    lastDisplayState = .failed
    lastPrefillTPS = nil
    view.updateTPS(nil)
    view.updateState(.failed)
    rebuildMenu(statusText: "Server: Crashed")
```

- [ ] **Step 7: Run tests — verify green**

```bash
swift test 2>&1
```

- [ ] **Step 8: Commit**

```bash
git add Sources/MLXManager/StatusBarController.swift Tests/
git commit -m "feat: add lastPrefillTPS to StatusBarController and updateTPS protocol method"
```

---

## Task 6: Add `tpsLabel` to `StatusBarView` (UI — manual verify)

**Files:**
- Modify: `Sources/MLXManagerApp/StatusBarView.swift`

This task touches AppKit layout — no unit test possible, verified manually.

- [ ] **Step 1: Add `tpsLabel` field**

In `Sources/MLXManagerApp/StatusBarView.swift`, add after `logLabel` (line 142):

```swift
private let tpsLabel: NSTextField
```

- [ ] **Step 2: Initialise `tpsLabel` in `init()`**

After `logLabel = NSTextField(labelWithString: "")` (line 148), add:

```swift
tpsLabel = NSTextField(labelWithString: "")
tpsLabel.font = NSFont.menuBarFont(ofSize: 0)
tpsLabel.textColor = NSColor.labelColor
tpsLabel.lineBreakMode = .byClipping
tpsLabel.isHidden = true
```

- [ ] **Step 3: Add to button and layout constraints**

After `button.addSubview(logLabel)` (line 162), add:

```swift
tpsLabel.translatesAutoresizingMaskIntoConstraints = false
button.addSubview(tpsLabel)
```

Replace the existing constraints (lines 165-171) with:

```swift
NSLayoutConstraint.activate([
    logLabel.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: pad),
    logLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
    tpsLabel.leadingAnchor.constraint(equalTo: logLabel.trailingAnchor, constant: pad),
    tpsLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
    arcView.leadingAnchor.constraint(equalTo: tpsLabel.trailingAnchor, constant: pad),
    arcView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -pad),
    arcView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
])
```

- [ ] **Step 4: Implement `updateTPS(_:)`**

Add after `updateLogLine(_:)` (line 285):

```swift
func updateTPS(_ tps: Double?) {
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if let tps {
            self.tpsLabel.stringValue = "\(Int(tps.rounded())) tok/s"
            self.tpsLabel.isHidden = false
        } else {
            self.tpsLabel.stringValue = ""
            self.tpsLabel.isHidden = true
        }
        self.recalculateWidth()
    }
}
```

- [ ] **Step 5: Extract `recalculateWidth()` helper and update `updateLogLine`**

The width calculation in `updateLogLine` (lines 275-283) needs to account for both labels. Extract a helper and call it from both update methods:

```swift
private func recalculateWidth() {
    let pad = Self.pad
    let arcWidth = arcView.intrinsicContentSize.width
    let font = logLabel.font ?? NSFont.menuBarFont(ofSize: 0)
    var total: CGFloat = pad + arcWidth + pad

    if !logLabel.isHidden {
        let w = (logLabel.stringValue as NSString).size(withAttributes: [.font: font]).width
        total += w + pad
    }
    if !tpsLabel.isHidden {
        let w = (tpsLabel.stringValue as NSString).size(withAttributes: [.font: font]).width
        total += w + pad
    }

    if logLabel.isHidden && tpsLabel.isHidden {
        statusItem.length = NSStatusItem.variableLength
    } else {
        statusItem.length = total
    }
}
```

Update `updateLogLine(_:)` to call `recalculateWidth()` instead of the inline calculation:

```swift
func updateLogLine(_ line: String?) {
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if let line {
            self.logLabel.stringValue = line
            self.logLabel.isHidden = false
        } else {
            self.logLabel.stringValue = ""
            self.logLabel.isHidden = true
        }
        self.recalculateWidth()
    }
}
```

- [ ] **Step 6: Build and run manually**

```bash
swift build 2>&1
```

Launch the app and verify: with `showPrefillTPS = false`, the label is absent. Enable the setting — after a qualifying request, `342 tok/s` appears between the log line and the arc icon.

- [ ] **Step 7: Commit**

```bash
git add Sources/MLXManagerApp/StatusBarView.swift
git commit -m "feat: add tpsLabel to StatusBarView between logLabel and arc icon"
```

---

## Task 7: Wire `showPrefillTPS` — settings checkbox + AppDelegate (RED → GREEN)

**Files:**
- Modify: `Sources/MLXManagerApp/SettingsWindowController.swift`
- Modify: `Sources/MLXManagerApp/AppDelegate.swift` (wire `updateTPS` on settings apply if needed)

This task is UI wiring — verified by build + manual test.

- [ ] **Step 1: Add checkbox to Settings General tab**

In `Sources/MLXManagerApp/SettingsWindowController.swift`, locate the "Show last log line" checkbox. Add a "Show prefill speed (tok/s)" checkbox immediately after it, following the exact same pattern.

Typical pattern (find by searching for `showLastLogLine`):
```swift
// After the showLastLogLine checkbox row:
let showPrefillTPSLabel = NSTextField(labelWithString: "Show prefill speed (tok/s):")
let showPrefillTPSCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(showPrefillTPSChanged(_:)))
showPrefillTPSCheckbox.state = settings.showPrefillTPS ? .on : .off
```

Add the corresponding `@objc` action:
```swift
@objc private func showPrefillTPSChanged(_ sender: NSButton) {
    settings.showPrefillTPS = sender.state == .on
}
```

And populate the field in `loadSettings()` (or wherever `showLastLogLine` is loaded):
```swift
showPrefillTPSCheckbox.state = settings.showPrefillTPS ? .on : .off
```

- [ ] **Step 2: Write failing tests for `applySettings` toggle**

In `Tests/MLXManagerTests/StatusBarControllerTests.swift`, add inside `struct StatusBarControllerTests` (uses Swift Testing — `@Test func`, `#expect`):

```swift
// MARK: - applySettings TPS wiring

@Test("applySettings enabling showPrefillTPS calls updateTPS with cached value")
func applySettings_enableShowPrefillTPS_callsUpdateTPSWithCachedValue() {
    let view = MockStatusBarView()
    var settings = AppSettings()
    settings.showPrefillTPS = false
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: settings, fileExists: { _ in true })
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    controller.update(state: state)
    view.lastTPSValue = .none   // reset spy
    var newSettings = settings
    newSettings.showPrefillTPS = true
    controller.applySettings(newSettings)
    if case .some(let tps) = view.lastTPSValue {
        #expect(tps != nil)
    } else {
        Issue.record("updateTPS was never called")
    }
}

@Test("applySettings disabling showPrefillTPS calls updateTPS(nil)")
func applySettings_disableShowPrefillTPS_callsUpdateTPSWithNil() {
    let view = MockStatusBarView()
    var settings = AppSettings()
    settings.showPrefillTPS = true
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: settings, fileExists: { _ in true })
    var state = ServerState()
    state.serverStarted()
    let t1 = Date()
    state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
    state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
    state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
    controller.update(state: state)
    view.lastTPSValue = .none   // reset spy
    var newSettings = settings
    newSettings.showPrefillTPS = false
    controller.applySettings(newSettings)
    if case .some(let tps) = view.lastTPSValue {
        #expect(tps == nil)
    } else {
        Issue.record("updateTPS was never called")
    }
}
```

- [ ] **Step 3: Run tests — verify RED**

```bash
swift test --filter StatusBarControllerTests/test_applySettings_showPrefillTPS 2>&1
```

Expected: FAIL — `applySettings` does not yet call `updateTPS`.

- [ ] **Step 4: Implement `applySettings` wiring in `StatusBarController`**

When settings change, `applySettings(_:)` is called on the controller. If `showPrefillTPS` was just enabled and `lastPrefillTPS != nil`, `updateTPS` should fire so the label appears immediately without waiting for the next request. Replace `applySettings(_:)` in `Sources/MLXManager/StatusBarController.swift`:

```swift
public func applySettings(_ settings: AppSettings) {
    currentSettings = settings
    if settings.showPrefillTPS {
        view.updateTPS(lastPrefillTPS)
    } else {
        view.updateTPS(nil)
    }
    rebuildMenu(statusText: statusText(for: lastDisplayState))
}
```

- [ ] **Step 5: Run tests — verify green**

```bash
swift test 2>&1
```

- [ ] **Step 6: Build**

```bash
swift build 2>&1
```

Expected: zero errors.

- [ ] **Step 7: Manual smoke test**

1. Launch app, open Settings → General
2. Confirm "Show prefill speed (tok/s)" checkbox is present and unchecked
3. Check it — no label appears yet (no qualifying measurement)
4. Run a request with a long prompt (needs ≥2 progress lines — large context)
5. Confirm `342 tok/s` (or similar) appears in menu bar between log line and icon
6. Uncheck the setting — label disappears immediately
7. Re-check — label reappears with last cached value

- [ ] **Step 8: Commit**

```bash
git add Sources/MLXManagerApp/SettingsWindowController.swift \
        Sources/MLXManager/StatusBarController.swift
git commit -m "feat: wire showPrefillTPS setting to checkbox and applySettings"
```

---

## Task 8: Final verification

- [ ] **Step 1: Run full test suite**

```bash
swift test 2>&1
```

Expected: all tests pass, zero failures.

- [ ] **Step 2: Build release**

```bash
swift build -c release 2>&1
```

Expected: clean build.

- [ ] **Step 3: Commit if any fixes needed, otherwise done**
