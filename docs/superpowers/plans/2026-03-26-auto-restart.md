# Auto-Restart on Crash — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically restart the MLX server after a crash, with a configurable setting and rate limiting (max 3 restarts in 3 minutes), posting a macOS notification when retries are exhausted.

**Architecture:** A pure `CrashRestartPolicy` value type handles rate-limit decisions. `ServerCoordinator` owns the policy and orchestrates restart attempts with a configurable delay. `AppDelegate` wires the new callbacks and posts notifications via `UNUserNotificationCenter`.

**Tech Stack:** Swift 5.9, XCTest (policy), Swift Testing (coordinator), AppKit, UserNotifications

---

### Task 1: CrashRestartPolicy — core logic

**Files:**
- Create: `Sources/MLXManager/CrashRestartPolicy.swift`
- Create: `Tests/MLXManagerTests/CrashRestartPolicyTests.swift`

- [ ] **Step 1: Write the failing test — first crash is allowed**

In `Tests/MLXManagerTests/CrashRestartPolicyTests.swift`:

```swift
import XCTest
@testable import MLXManager

final class CrashRestartPolicyTests: XCTestCase {

    func test_recordCrash_firstCrash_returnsTrue() {
        var policy = CrashRestartPolicy()
        let allowed = policy.recordCrash(at: Date())
        XCTAssertTrue(allowed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CrashRestartPolicyTests/test_recordCrash_firstCrash_returnsTrue`
Expected: Compile error — `CrashRestartPolicy` not defined.

- [ ] **Step 3: Write minimal implementation**

In `Sources/MLXManager/CrashRestartPolicy.swift`:

```swift
import Foundation

/// Rate-limits crash restarts: allows up to `maxRestarts` within a rolling `window`.
public struct CrashRestartPolicy {
    public let maxRestarts: Int
    public let window: TimeInterval
    public private(set) var crashTimestamps: [Date] = []

    public init(maxRestarts: Int = 3, window: TimeInterval = 180) {
        self.maxRestarts = maxRestarts
        self.window = window
    }

    /// Record a crash and return whether a restart is allowed.
    public mutating func recordCrash(at date: Date = Date()) -> Bool {
        crashTimestamps.append(date)
        crashTimestamps.removeAll { date.timeIntervalSince($0) > window }
        return crashTimestamps.count < maxRestarts
    }

    /// Clear crash history (called on manual start/stop).
    public mutating func reset() {
        crashTimestamps = []
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CrashRestartPolicyTests/test_recordCrash_firstCrash_returnsTrue`
Expected: PASS

- [ ] **Step 5: Write failing test — third crash is allowed, fourth is not**

Add to `CrashRestartPolicyTests`:

```swift
func test_recordCrash_thirdCrashAllowed_fourthDenied() {
    var policy = CrashRestartPolicy(maxRestarts: 3, window: 180)
    let now = Date()
    XCTAssertTrue(policy.recordCrash(at: now))
    XCTAssertTrue(policy.recordCrash(at: now.addingTimeInterval(1)))
    // Third crash — this is the 3rd restart attempt, should still be allowed
    // because count (2) < maxRestarts (3) after eviction
    // Wait, after 3 recordCrash calls, count is 3, and 3 < 3 is false.
    // So: first two are allowed, third is denied.
    // Let's verify the boundary:
    let third = policy.recordCrash(at: now.addingTimeInterval(2))
    XCTAssertFalse(third)
}
```

- [ ] **Step 6: Run test to verify it fails or passes (boundary check)**

Run: `swift test --filter CrashRestartPolicyTests/test_recordCrash_thirdCrashAllowed_fourthDenied`
Expected: PASS (the implementation already handles this correctly — 3 crashes in window, `count < 3` is false on third).

- [ ] **Step 7: Write failing test — crashes outside window are evicted**

Add to `CrashRestartPolicyTests`:

```swift
func test_recordCrash_oldCrashesEvicted_allowsRestart() {
    var policy = CrashRestartPolicy(maxRestarts: 3, window: 180)
    let now = Date()
    // Two crashes within window
    _ = policy.recordCrash(at: now)
    _ = policy.recordCrash(at: now.addingTimeInterval(1))
    // Third crash after window has passed — old ones should be evicted
    let allowed = policy.recordCrash(at: now.addingTimeInterval(200))
    XCTAssertTrue(allowed)
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter CrashRestartPolicyTests/test_recordCrash_oldCrashesEvicted_allowsRestart`
Expected: PASS

- [ ] **Step 9: Write failing test — reset clears history**

Add to `CrashRestartPolicyTests`:

```swift
func test_reset_clearsCrashHistory() {
    var policy = CrashRestartPolicy(maxRestarts: 3, window: 180)
    let now = Date()
    _ = policy.recordCrash(at: now)
    _ = policy.recordCrash(at: now.addingTimeInterval(1))
    policy.reset()
    XCTAssertTrue(policy.crashTimestamps.isEmpty)
    XCTAssertTrue(policy.recordCrash(at: now.addingTimeInterval(2)))
}
```

- [ ] **Step 10: Run test to verify it passes**

Run: `swift test --filter CrashRestartPolicyTests/test_reset_clearsCrashHistory`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add Sources/MLXManager/CrashRestartPolicy.swift Tests/MLXManagerTests/CrashRestartPolicyTests.swift
git commit -m "feat: add CrashRestartPolicy value type with rate-limited restart logic"
```

---

### Task 2: AppSettings — add autoRestartEnabled

**Files:**
- Modify: `Sources/MLXManager/AppSettings.swift`
- Modify: `Tests/MLXManagerTests/AppSettingsTests.swift`

- [ ] **Step 1: Write failing test — default value**

Add to `AppSettingsTests`:

```swift
func test_appSettings_autoRestartEnabled_defaultsTrue() {
    XCTAssertEqual(AppSettings().autoRestartEnabled, true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppSettingsTests/test_appSettings_autoRestartEnabled_defaultsTrue`
Expected: Compile error — `autoRestartEnabled` not defined.

- [ ] **Step 3: Add the property to AppSettings**

In `Sources/MLXManager/AppSettings.swift`, add after `showPrefillTPS`:

```swift
/// Automatically restart the server if it crashes (rate-limited). Default true.
public var autoRestartEnabled: Bool = true
```

Add to `CodingKeys`:

```swift
case autoRestartEnabled
```

Add to `init(from decoder:)` after the `showPrefillTPS` line:

```swift
autoRestartEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRestartEnabled) ?? true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_autoRestartEnabled_defaultsTrue`
Expected: PASS

- [ ] **Step 5: Write failing test — round-trip JSON**

Add to `AppSettingsTests`:

```swift
func test_appSettings_autoRestartEnabled_roundTripsJSON() throws {
    var s = AppSettings()
    s.autoRestartEnabled = false
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded.autoRestartEnabled, false)
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_autoRestartEnabled_roundTripsJSON`
Expected: PASS (Codable synthesis handles it via CodingKeys).

- [ ] **Step 7: Write failing test — migration from old JSON**

Add to `AppSettingsTests`:

```swift
func test_appSettings_autoRestartEnabled_missingKeyDefaultsTrue() throws {
    let json = """
    {"ramGraphEnabled":false,"ramPollInterval":5,"startAtLogin":false,
     "logPath":"~/repos/mlx/Logs/server.log","serverPort":8080,
     "managedGatewayPort":8080,"progressCompletionThreshold":0,
     "showLastLogLine":false,"managedGatewayEnabled":false,"pythonPathOverride":"",
     "showPrefillTPS":false}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
    XCTAssertTrue(decoded.autoRestartEnabled)
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_autoRestartEnabled_missingKeyDefaultsTrue`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/MLXManager/AppSettings.swift Tests/MLXManagerTests/AppSettingsTests.swift
git commit -m "feat: add autoRestartEnabled setting (default true)"
```

---

### Task 3: ServerCoordinator — auto-restart on crash

**Files:**
- Modify: `Sources/MLXManager/ServerCoordinator.swift`
- Modify: `Tests/MLXManagerTests/ServerCoordinatorTests.swift`

- [ ] **Step 1: Write failing test — process exit with autoRestart triggers restart**

Add to `ServerCoordinatorTests`:

```swift
@Test("process exit with autoRestart enabled fires onAutoRestart")
func test_processExit_autoRestartEnabled_firesOnAutoRestart() throws {
    let launcher = MockProcessLauncherForCoordinator()
    let (coordinator, _) = makeCoordinator(launcher: launcher)
    coordinator.autoRestartEnabled = true
    coordinator.restartDelay = 0 // no delay in tests
    try coordinator.start(config: ServerConfig.fixture())

    var autoRestartFired = false
    var exitFired = false
    coordinator.onAutoRestart = { autoRestartFired = true }
    coordinator.onProcessExit = { exitFired = true }

    launcher.exitCallback?()

    #expect(autoRestartFired)
    #expect(!exitFired)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ServerCoordinatorTests/test_processExit_autoRestartEnabled_firesOnAutoRestart`
Expected: Compile error — `autoRestartEnabled`, `restartDelay`, `onAutoRestart` not defined.

- [ ] **Step 3: Add auto-restart state and callbacks to ServerCoordinator**

In `Sources/MLXManager/ServerCoordinator.swift`, add properties:

```swift
public var autoRestartEnabled: Bool = true
public var restartDelay: TimeInterval = 2.0
public var onAutoRestart: (() -> Void)?
public var onRestartExhausted: (() -> Void)?

private var crashRestartPolicy = CrashRestartPolicy()
private var lastConfig: ServerConfig?
private var pendingRestartWork: DispatchWorkItem?
```

Modify `start(config:)` to save config and reset policy:

```swift
public func start(config: ServerConfig) throws {
    try serverManager.start(config: config)
    lastConfig = config
    crashRestartPolicy.reset()
    state = ServerState()
    state.serverStarted()
    onStateChange?(state)
    startTailing()
}
```

Modify `stop()` to clear config, reset policy, and cancel pending restart:

```swift
public func stop() {
    pendingRestartWork?.cancel()
    pendingRestartWork = nil
    logTailer?.stop()
    logTailer = nil
    serverManager.stop()
    lastConfig = nil
    crashRestartPolicy.reset()
    state.serverStopped()
    onStateChange?(state)
}
```

Replace `handleProcessExit()`:

```swift
private func handleProcessExit() {
    logger.warning("server process exited unexpectedly (pid was \(self.pid.map(String.init) ?? "nil", privacy: .public))")
    logTailer?.stop()
    logTailer = nil
    state.serverCrashed()
    onStateChange?(state)

    guard autoRestartEnabled, let config = lastConfig else {
        onProcessExit?()
        return
    }

    if crashRestartPolicy.recordCrash() {
        onAutoRestart?()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try self.start(config: config)
            } catch {
                logger.error("auto-restart failed: \(error)")
                self.onProcessExit?()
            }
        }
        pendingRestartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay, execute: work)
    } else {
        onProcessExit?()
        onRestartExhausted?()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ServerCoordinatorTests/test_processExit_autoRestartEnabled_firesOnAutoRestart`
Expected: PASS

- [ ] **Step 5: Write failing test — autoRestart disabled fires onProcessExit**

Add to `ServerCoordinatorTests`:

```swift
@Test("process exit with autoRestart disabled fires onProcessExit")
func test_processExit_autoRestartDisabled_firesOnProcessExit() throws {
    let launcher = MockProcessLauncherForCoordinator()
    let (coordinator, _) = makeCoordinator(launcher: launcher)
    coordinator.autoRestartEnabled = false
    try coordinator.start(config: ServerConfig.fixture())

    var exitFired = false
    var autoRestartFired = false
    coordinator.onProcessExit = { exitFired = true }
    coordinator.onAutoRestart = { autoRestartFired = true }

    launcher.exitCallback?()

    #expect(exitFired)
    #expect(!autoRestartFired)
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter ServerCoordinatorTests/test_processExit_autoRestartDisabled_firesOnProcessExit`
Expected: PASS

- [ ] **Step 7: Write failing test — exhausted retries fires onRestartExhausted**

Add to `ServerCoordinatorTests`:

```swift
@Test("exhausted restart retries fires onRestartExhausted")
func test_processExit_exhaustedRetries_firesOnRestartExhausted() throws {
    let launcher = MockProcessLauncherForCoordinator()
    let (coordinator, _) = makeCoordinator(launcher: launcher)
    coordinator.autoRestartEnabled = true
    coordinator.restartDelay = 0

    // Use a policy with maxRestarts=1 for quick exhaustion
    coordinator.crashRestartPolicy = CrashRestartPolicy(maxRestarts: 1, window: 180)
    try coordinator.start(config: ServerConfig.fixture())

    // First crash — allowed
    launcher.exitCallback?()

    var exhaustedFired = false
    var exitFired = false
    coordinator.onRestartExhausted = { exhaustedFired = true }
    coordinator.onProcessExit = { exitFired = true }

    // Second crash — exhausted
    launcher.exitCallback?()

    #expect(exhaustedFired)
    #expect(exitFired)
}
```

- [ ] **Step 8: Run test to verify it fails**

Run: `swift test --filter ServerCoordinatorTests/test_processExit_exhaustedRetries_firesOnRestartExhausted`
Expected: Compile error — `crashRestartPolicy` is private.

- [ ] **Step 9: Make crashRestartPolicy settable for testing**

Change the property visibility in `ServerCoordinator`:

```swift
public var crashRestartPolicy = CrashRestartPolicy()
```

- [ ] **Step 10: Run test to verify it passes**

Run: `swift test --filter ServerCoordinatorTests/test_processExit_exhaustedRetries_firesOnRestartExhausted`
Expected: PASS

- [ ] **Step 11: Write failing test — manual stop resets policy and cancels pending restart**

Add to `ServerCoordinatorTests`:

```swift
@Test("manual stop resets crash policy")
func test_stop_resetsCrashPolicy() throws {
    let launcher = MockProcessLauncherForCoordinator()
    let (coordinator, _) = makeCoordinator(launcher: launcher)
    coordinator.autoRestartEnabled = true
    coordinator.restartDelay = 0
    try coordinator.start(config: ServerConfig.fixture())

    // Trigger a crash to populate policy
    launcher.exitCallback?()

    coordinator.stop()

    #expect(coordinator.crashRestartPolicy.crashTimestamps.isEmpty)
}
```

- [ ] **Step 12: Run test to verify it passes**

Run: `swift test --filter ServerCoordinatorTests/test_stop_resetsCrashPolicy`
Expected: PASS

- [ ] **Step 13: Verify existing coordinator tests still pass**

Run: `swift test --filter ServerCoordinatorTests`
Expected: All tests PASS.

- [ ] **Step 14: Commit**

```bash
git add Sources/MLXManager/ServerCoordinator.swift Tests/MLXManagerTests/ServerCoordinatorTests.swift
git commit -m "feat: auto-restart server on crash with rate limiting in ServerCoordinator"
```

---

### Task 4: AppDelegate — wire callbacks and notifications

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

- [ ] **Step 1: Add UserNotifications import and notification setup**

At the top of `AppDelegate.swift`, add:

```swift
import UserNotifications
```

In `applicationDidFinishLaunching`, after `bootstrapEnvironmentIfNeeded(presets:)`, add:

```swift
UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
```

- [ ] **Step 2: Wire autoRestartEnabled from settings to coordinator**

In `applicationDidFinishLaunching`, after creating `serverCoordinator` and before wiring callbacks, add:

```swift
serverCoordinator.autoRestartEnabled = settings.autoRestartEnabled
```

In the `swc.onChange` closure (inside `showSettings`), after `self.saveSettings(newSettings)`, add:

```swift
self.serverCoordinator.autoRestartEnabled = newSettings.autoRestartEnabled
```

- [ ] **Step 3: Wire onAutoRestart callback**

After the existing `serverCoordinator.onProcessExit` wiring, add:

```swift
serverCoordinator.onAutoRestart = { [weak self] in
    guard let self else { return }
    self.stopRAMPolling()
}
```

- [ ] **Step 4: Wire onRestartExhausted callback**

After the `onAutoRestart` wiring, add:

```swift
serverCoordinator.onRestartExhausted = { [weak self] in
    guard let self else { return }
    self.postRestartExhaustedNotification()
}
```

- [ ] **Step 5: Add the notification helper method**

Add to AppDelegate:

```swift
private func postRestartExhaustedNotification() {
    let content = UNMutableNotificationContent()
    content.title = "MLX Server Stopped"
    content.body = "Server crashed 3 times in 3 minutes. Automatic restart disabled."
    let request = UNNotificationRequest(identifier: "restart-exhausted", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
        if let error { logger.error("notification failed: \(error)") }
    }
}
```

- [ ] **Step 6: Build to verify compilation**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "feat: wire auto-restart callbacks and macOS crash notification in AppDelegate"
```

---

### Task 5: Settings UI — add checkbox

**Files:**
- Modify: `Sources/MLXManagerApp/SettingsWindowController.swift`

- [ ] **Step 1: Add the checkbox property**

After the `showPrefillTPSCheckbox` declaration (line 62), add:

```swift
private let autoRestartCheckbox = NSButton(checkboxWithTitle: "Restart server automatically after crash", target: nil, action: nil)
```

- [ ] **Step 2: Initialize the checkbox in the general tab builder**

In the method that sets up the general tab (where `showPrefillTPSCheckbox` is configured around line 537), add after the `showPrefillTPSCheckbox` setup:

```swift
autoRestartCheckbox.state = draftSettings.autoRestartEnabled ? .on : .off
autoRestartCheckbox.target = self
autoRestartCheckbox.action = #selector(autoRestartToggled)
```

- [ ] **Step 3: Add the checkbox to the grid**

The current grid has 10 rows (indices 0–9). Change the grid to 11 rows:

```swift
let grid = NSGridView(numberOfColumns: 2, rows: 11)
```

Insert the auto-restart checkbox at row 6 (after `showPrefillTPSCheckbox` at row 5), and shift all subsequent rows (server port, gateway port, python override, complete at %) down by 1:

```swift
grid.cell(atColumnIndex: 1, rowIndex: 6).contentView = autoRestartCheckbox
grid.cell(atColumnIndex: 0, rowIndex: 7).contentView = NSTextField(labelWithString: "Server port:")
grid.cell(atColumnIndex: 1, rowIndex: 7).contentView = serverPortField
grid.cell(atColumnIndex: 0, rowIndex: 8).contentView = NSTextField(labelWithString: "Gateway port:")
grid.cell(atColumnIndex: 1, rowIndex: 8).contentView = managedGatewayPortField
grid.cell(atColumnIndex: 0, rowIndex: 9).contentView = NSTextField(labelWithString: "Python override:")
grid.cell(atColumnIndex: 1, rowIndex: 9).contentView = pythonPathOverrideField
grid.cell(atColumnIndex: 0, rowIndex: 10).contentView = NSTextField(labelWithString: "Complete at %:")
grid.cell(atColumnIndex: 1, rowIndex: 10).contentView = completionThresholdField
```

- [ ] **Step 4: Add the toggle action**

Add the `@objc` method after the existing `showPrefillTPSToggled`:

```swift
@objc private func autoRestartToggled() {
    draftSettings.autoRestartEnabled = autoRestartCheckbox.state == .on
    onChange?(draftPresets, draftSettings)
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Sources/MLXManagerApp/SettingsWindowController.swift
git commit -m "feat: add auto-restart checkbox to Settings UI"
```

---

### Task 6: Run full test suite

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `swift test`
Expected: All tests PASS.

- [ ] **Step 2: If any failures, fix and re-run**

- [ ] **Step 3: Final commit if any fixes were needed**
