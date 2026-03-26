# Package Auto-Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Periodically check for mlx-lm/mlx-vlm package updates, auto-upgrade both venvs, and notify the user to restart the server when updates are applied while it's running.

**Architecture:** A `PackageUpdateChecker` struct handles the check (`uv pip list --outdated`) and upgrade (`uv pip install --upgrade`) phases using the existing `CommandRunner` protocol and `UVLocator`. An `UpdateScheduler` manages timer-based scheduling using persisted `lastUpdateCheck` timestamps in `AppSettings`. The `StatusBarController` gains a "Restart to apply updates" menu item and macOS notifications are posted via `UNUserNotificationCenter`.

**Tech Stack:** Swift 5.9+, XCTest, GCD (DispatchQueue), UNUserNotificationCenter, existing `CommandRunner`/`UVLocator` infrastructure.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/MLXManager/PackageUpdateChecker.swift` | Create | Parse `uv pip list --outdated`, run `uv pip install --upgrade` |
| `Sources/MLXManager/UpdateScheduler.swift` | Create | Timer management, last-check persistence, trigger check/upgrade |
| `Sources/MLXManager/AppSettings.swift` | Modify | Add `updateCheckInterval`, `lastUpdateCheck`, `restartNeeded` |
| `Sources/MLXManager/StatusBarController.swift` | Modify | Add "Restart to apply updates" menu item |
| `Tests/MLXManagerTests/PackageUpdateCheckerTests.swift` | Create | Tests for parsing + upgrade commands |
| `Tests/MLXManagerTests/UpdateSchedulerTests.swift` | Create | Tests for scheduling logic |
| `Tests/MLXManagerTests/AppSettingsTests.swift` | Modify | Tests for new settings fields |

---

## Task 1: Add new settings fields to AppSettings

**Files:**
- Modify: `Sources/MLXManager/AppSettings.swift`
- Modify: `Tests/MLXManagerTests/AppSettingsTests.swift`

- [ ] **Step 1: Write failing test for `updateCheckInterval` default**

```swift
func test_appSettings_updateCheckInterval_defaultsTo0() {
    XCTAssertEqual(AppSettings().updateCheckInterval, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppSettingsTests/test_appSettings_updateCheckInterval_defaultsTo0`
Expected: FAIL — `AppSettings` has no member `updateCheckInterval`

- [ ] **Step 3: Add `updateCheckInterval` property to AppSettings**

In `AppSettings.swift`, add the property, the coding key, and the decode line:

```swift
// Property (after showPrefillTPS):
/// Hours between package update checks. 0 = off. Allowed: 0, 6, 12, 24.
public var updateCheckInterval: Int = 0
```

```swift
// CodingKeys (add case):
case updateCheckInterval
```

```swift
// init(from decoder:) (add at end):
updateCheckInterval = try container.decodeIfPresent(Int.self, forKey: .updateCheckInterval) ?? 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_updateCheckInterval_defaultsTo0`
Expected: PASS

- [ ] **Step 5: Write failing test for `updateCheckInterval` round-trip**

```swift
func test_appSettings_updateCheckInterval_roundTripsJSON() throws {
    var s = AppSettings()
    s.updateCheckInterval = 12
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded.updateCheckInterval, 12)
}
```

- [ ] **Step 6: Run test to verify it passes** (should already pass with the Codable implementation)

Run: `swift test --filter AppSettingsTests/test_appSettings_updateCheckInterval_roundTripsJSON`
Expected: PASS

- [ ] **Step 7: Write failing test for `updateCheckInterval` migration from old JSON**

```swift
func test_appSettings_updateCheckInterval_migratesFromOldJSON() throws {
    let json = """
    {"ramGraphEnabled":false,"ramPollInterval":5,"startAtLogin":false,
     "logPath":"~/repos/mlx/Logs/server.log","serverPort":8080,
     "managedGatewayPort":8080,"progressCompletionThreshold":0,
     "showLastLogLine":false,"managedGatewayEnabled":false,"pythonPathOverride":"",
     "showPrefillTPS":false}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
    XCTAssertEqual(decoded.updateCheckInterval, 0)
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_updateCheckInterval_migratesFromOldJSON`
Expected: PASS

- [ ] **Step 9: Write failing test for `lastUpdateCheck` default**

```swift
func test_appSettings_lastUpdateCheck_defaultsToNil() {
    XCTAssertNil(AppSettings().lastUpdateCheck)
}
```

- [ ] **Step 10: Run test to verify it fails**

Run: `swift test --filter AppSettingsTests/test_appSettings_lastUpdateCheck_defaultsToNil`
Expected: FAIL — no member `lastUpdateCheck`

- [ ] **Step 11: Add `lastUpdateCheck` property to AppSettings**

```swift
// Property:
/// Timestamp of last successful package update check.
public var lastUpdateCheck: Date? = nil
```

```swift
// CodingKeys:
case lastUpdateCheck
```

```swift
// init(from decoder:):
lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
```

- [ ] **Step 12: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_lastUpdateCheck_defaultsToNil`
Expected: PASS

- [ ] **Step 13: Write failing test for `lastUpdateCheck` round-trip**

```swift
func test_appSettings_lastUpdateCheck_roundTripsJSON() throws {
    var s = AppSettings()
    s.lastUpdateCheck = Date(timeIntervalSince1970: 1711500000)
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded.lastUpdateCheck, s.lastUpdateCheck)
}
```

- [ ] **Step 14: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_lastUpdateCheck_roundTripsJSON`
Expected: PASS

- [ ] **Step 15: Write failing test for `restartNeeded` default**

```swift
func test_appSettings_restartNeeded_defaultsFalse() {
    XCTAssertEqual(AppSettings().restartNeeded, false)
}
```

- [ ] **Step 16: Run test to verify it fails**

Run: `swift test --filter AppSettingsTests/test_appSettings_restartNeeded_defaultsFalse`
Expected: FAIL — no member `restartNeeded`

- [ ] **Step 17: Add `restartNeeded` property to AppSettings**

```swift
// Property:
/// Set after a package upgrade completes while the server is running.
public var restartNeeded: Bool = false
```

```swift
// CodingKeys:
case restartNeeded
```

```swift
// init(from decoder:):
restartNeeded = try container.decodeIfPresent(Bool.self, forKey: .restartNeeded) ?? false
```

- [ ] **Step 18: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_restartNeeded_defaultsFalse`
Expected: PASS

- [ ] **Step 19: Write failing test for `restartNeeded` round-trip**

```swift
func test_appSettings_restartNeeded_roundTripsJSON() throws {
    var s = AppSettings()
    s.restartNeeded = true
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded.restartNeeded, true)
}
```

- [ ] **Step 20: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests/test_appSettings_restartNeeded_roundTripsJSON`
Expected: PASS

- [ ] **Step 21: Run full AppSettings test suite**

Run: `swift test --filter AppSettingsTests`
Expected: All PASS

- [ ] **Step 22: Commit**

```bash
git add Sources/MLXManager/AppSettings.swift Tests/MLXManagerTests/AppSettingsTests.swift
git commit -m "feat: add updateCheckInterval, lastUpdateCheck, restartNeeded to AppSettings"
```

---

## Task 2: PackageUpdateChecker — parsing `uv pip list --outdated`

**Files:**
- Create: `Sources/MLXManager/PackageUpdateChecker.swift`
- Create: `Tests/MLXManagerTests/PackageUpdateCheckerTests.swift`

- [ ] **Step 1: Write failing test for parsing outdated output with updates**

`uv pip list --outdated` produces tab-separated output like:
```
Package    Version    Latest    Type
mlx-lm     0.21.0     0.22.1    sdist
```

```swift
import XCTest
@testable import MLXManager

final class PackageUpdateCheckerTests: XCTestCase {

    func test_parseOutdated_withUpdates_returnsPackageInfo() {
        let output = """
        Package    Version    Latest    Type
        mlx-lm     0.21.0     0.22.1    sdist
        """
        let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.currentVersion, "0.21.0")
        XCTAssertEqual(result?.latestVersion, "0.22.1")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PackageUpdateCheckerTests/test_parseOutdated_withUpdates_returnsPackageInfo`
Expected: FAIL — no such module/type

- [ ] **Step 3: Write minimal PackageUpdateChecker with parsing**

Create `Sources/MLXManager/PackageUpdateChecker.swift`:

```swift
import Foundation

/// Result of checking a single package for updates.
public struct OutdatedPackage: Equatable {
    public let name: String
    public let currentVersion: String
    public let latestVersion: String
}

/// Checks for and applies mlx-lm/mlx-vlm package updates using `uv`.
public struct PackageUpdateChecker {

    /// Parse `uv pip list --outdated` output for a specific package.
    /// Returns nil if the package is not in the outdated list.
    public static func parseOutdated(output: String, packageName: String) -> OutdatedPackage? {
        for line in output.components(separatedBy: .newlines) {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 3 else { continue }
            let name = String(columns[0])
            if name.lowercased() == packageName.lowercased() {
                return OutdatedPackage(
                    name: name,
                    currentVersion: String(columns[1]),
                    latestVersion: String(columns[2])
                )
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PackageUpdateCheckerTests/test_parseOutdated_withUpdates_returnsPackageInfo`
Expected: PASS

- [ ] **Step 5: Write failing test for no updates**

```swift
func test_parseOutdated_noUpdates_returnsNil() {
    let output = """
    Package    Version    Latest    Type
    """
    let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
    XCTAssertNil(result)
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter PackageUpdateCheckerTests/test_parseOutdated_noUpdates_returnsNil`
Expected: PASS (already handled)

- [ ] **Step 7: Write failing test for empty output**

```swift
func test_parseOutdated_emptyOutput_returnsNil() {
    let result = PackageUpdateChecker.parseOutdated(output: "", packageName: "mlx-lm")
    XCTAssertNil(result)
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter PackageUpdateCheckerTests/test_parseOutdated_emptyOutput_returnsNil`
Expected: PASS

- [ ] **Step 9: Write failing test for package not in list (other packages outdated)**

```swift
func test_parseOutdated_differentPackageOutdated_returnsNil() {
    let output = """
    Package    Version    Latest    Type
    numpy      1.25.0     1.26.0    sdist
    """
    let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
    XCTAssertNil(result)
}
```

- [ ] **Step 10: Run test to verify it passes**

Run: `swift test --filter PackageUpdateCheckerTests/test_parseOutdated_differentPackageOutdated_returnsNil`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add Sources/MLXManager/PackageUpdateChecker.swift Tests/MLXManagerTests/PackageUpdateCheckerTests.swift
git commit -m "feat: add PackageUpdateChecker with outdated output parsing"
```

---

## Task 3: PackageUpdateChecker — check and upgrade commands

**Files:**
- Modify: `Sources/MLXManager/PackageUpdateChecker.swift`
- Modify: `Tests/MLXManagerTests/PackageUpdateCheckerTests.swift`

The `SpyCommandRunner` from `EnvironmentBootstrapperTests.swift` is reused here. It lives in that test file, so we need to either move it to a shared location or duplicate it. Since the project keeps test doubles local, we'll define a minimal spy in this test file.

- [ ] **Step 1: Write failing test for check command execution**

Add the test double and first test to the test file:

```swift
final class SpyRunner: CommandRunner {
    struct Call: Equatable {
        let command: String
        let arguments: [String]
    }
    var calls: [Call] = []
    var outputByArgPrefix: [String: String] = [:]
    var exitCode: Int32 = 0

    func run(command: String, arguments: [String], onOutput: @escaping (String) -> Void) -> Int32 {
        calls.append(Call(command: command, arguments: arguments))
        if let prefix = arguments.first, let output = outputByArgPrefix[prefix] {
            onOutput(output)
        }
        return exitCode
    }
}

func test_checkForUpdates_runsOutdatedCommandForBothVenvs() {
    let spy = SpyRunner()
    let uvPath = "/usr/local/bin/uv"
    let checker = PackageUpdateChecker(
        uvPath: uvPath,
        runner: spy
    )

    checker.checkForUpdates { _ in }

    let outdatedCalls = spy.calls.filter { $0.arguments.contains("--outdated") }
    XCTAssertEqual(outdatedCalls.count, 2)

    let pythonPaths = outdatedCalls.compactMap { call -> String? in
        guard let idx = call.arguments.firstIndex(of: "--python"),
              idx + 1 < call.arguments.count else { return nil }
        return call.arguments[idx + 1]
    }
    XCTAssertTrue(pythonPaths.contains(EnvironmentBootstrapper.pythonPath(for: .mlxLM)))
    XCTAssertTrue(pythonPaths.contains(EnvironmentBootstrapper.pythonPath(for: .mlxVLM)))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PackageUpdateCheckerTests/test_checkForUpdates_runsOutdatedCommandForBothVenvs`
Expected: FAIL — `PackageUpdateChecker` has no init with `uvPath`/`runner`

- [ ] **Step 3: Add instance-based check method to PackageUpdateChecker**

Add to `PackageUpdateChecker.swift`:

```swift
public struct PackageUpdateChecker {
    private let uvPath: String
    private let runner: CommandRunner

    public init(uvPath: String, runner: CommandRunner) {
        self.uvPath = uvPath
        self.runner = runner
    }

    /// Result of checking both venvs for updates.
    public struct CheckResult: Equatable {
        public let mlxLM: OutdatedPackage?
        public let mlxVLM: OutdatedPackage?

        public var hasUpdates: Bool { mlxLM != nil || mlxVLM != nil }
    }

    /// Check both venvs for outdated packages. Calls completion on the calling thread.
    public func checkForUpdates(completion: @escaping (CheckResult) -> Void) {
        let lmPython = EnvironmentBootstrapper.pythonPath(for: .mlxLM)
        let vlmPython = EnvironmentBootstrapper.pythonPath(for: .mlxVLM)

        let lmOutput = runList(python: lmPython)
        let vlmOutput = runList(python: vlmPython)

        let result = CheckResult(
            mlxLM: Self.parseOutdated(output: lmOutput, packageName: "mlx-lm"),
            mlxVLM: Self.parseOutdated(output: vlmOutput, packageName: "mlx-vlm")
        )
        completion(result)
    }

    private func runList(python: String) -> String {
        var output = ""
        _ = runner.run(
            command: uvPath,
            arguments: ["pip", "list", "--outdated", "--python", python],
            onOutput: { output += $0 }
        )
        return output
    }

    // ... existing parseOutdated stays as-is ...
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PackageUpdateCheckerTests/test_checkForUpdates_runsOutdatedCommandForBothVenvs`
Expected: PASS

- [ ] **Step 5: Write failing test for upgrade command execution**

```swift
func test_upgrade_runsInstallUpgradeForBothVenvs() {
    let spy = SpyRunner()
    let checker = PackageUpdateChecker(uvPath: "/usr/local/bin/uv", runner: spy)

    checker.upgrade { _ in }

    let upgradeCalls = spy.calls.filter { $0.arguments.contains("--upgrade") }
    XCTAssertEqual(upgradeCalls.count, 2)

    let packages = upgradeCalls.compactMap { call -> String? in
        guard let idx = call.arguments.firstIndex(of: "--upgrade") else { return nil }
        // Package name is before --python: ["pip", "install", "--upgrade", "mlx-lm", "--python", path]
        return call.arguments.first(where: { $0 == "mlx-lm" || $0 == "mlx-vlm" })
    }
    XCTAssertTrue(packages.contains("mlx-lm"))
    XCTAssertTrue(packages.contains("mlx-vlm"))
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `swift test --filter PackageUpdateCheckerTests/test_upgrade_runsInstallUpgradeForBothVenvs`
Expected: FAIL — no method `upgrade`

- [ ] **Step 7: Add upgrade method**

Add to `PackageUpdateChecker`:

```swift
/// Upgrade both venvs. Returns true if both succeed.
public func upgrade(completion: @escaping (Bool) -> Void) {
    let lmPython = EnvironmentBootstrapper.pythonPath(for: .mlxLM)
    let vlmPython = EnvironmentBootstrapper.pythonPath(for: .mlxVLM)

    let lmOK = runUpgrade(package: "mlx-lm", python: lmPython)
    let vlmOK = runUpgrade(package: "mlx-vlm", python: vlmPython)

    completion(lmOK && vlmOK)
}

private func runUpgrade(package: String, python: String) -> Bool {
    let code = runner.run(
        command: uvPath,
        arguments: ["pip", "install", "--upgrade", package, "--python", python],
        onOutput: { _ in }
    )
    return code == 0
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter PackageUpdateCheckerTests/test_upgrade_runsInstallUpgradeForBothVenvs`
Expected: PASS

- [ ] **Step 9: Write failing test for upgrade failure**

```swift
func test_upgrade_returnsFalseOnFailure() {
    let spy = SpyRunner()
    spy.exitCode = 1
    let checker = PackageUpdateChecker(uvPath: "/usr/local/bin/uv", runner: spy)

    var result = true
    checker.upgrade { result = $0 }

    XCTAssertFalse(result)
}
```

- [ ] **Step 10: Run test to verify it passes**

Run: `swift test --filter PackageUpdateCheckerTests/test_upgrade_returnsFalseOnFailure`
Expected: PASS

- [ ] **Step 11: Run full PackageUpdateChecker test suite**

Run: `swift test --filter PackageUpdateCheckerTests`
Expected: All PASS

- [ ] **Step 12: Commit**

```bash
git add Sources/MLXManager/PackageUpdateChecker.swift Tests/MLXManagerTests/PackageUpdateCheckerTests.swift
git commit -m "feat: add check and upgrade commands to PackageUpdateChecker"
```

---

## Task 4: UpdateScheduler — timer and scheduling logic

**Files:**
- Create: `Sources/MLXManager/UpdateScheduler.swift`
- Create: `Tests/MLXManagerTests/UpdateSchedulerTests.swift`

- [ ] **Step 1: Write failing test for immediate check when lastUpdateCheck is nil**

```swift
import XCTest
@testable import MLXManager

final class UpdateSchedulerTests: XCTestCase {

    func test_evaluate_nilLastCheck_returnsCheckNow() {
        let result = UpdateScheduler.evaluate(
            interval: 12,
            lastCheck: nil,
            now: Date()
        )
        XCTAssertEqual(result, .checkNow)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdateSchedulerTests/test_evaluate_nilLastCheck_returnsCheckNow`
Expected: FAIL — no type `UpdateScheduler`

- [ ] **Step 3: Write minimal UpdateScheduler**

Create `Sources/MLXManager/UpdateScheduler.swift`:

```swift
import Foundation

/// Determines when the next package update check should run.
public struct UpdateScheduler {

    public enum Action: Equatable {
        case checkNow
        case scheduleAfter(TimeInterval)
        case disabled
    }

    /// Evaluate what action to take based on current settings.
    /// - Parameters:
    ///   - interval: Hours between checks. 0 means disabled.
    ///   - lastCheck: Timestamp of last successful check, or nil if never checked.
    ///   - now: Current time.
    public static func evaluate(interval: Int, lastCheck: Date?, now: Date) -> Action {
        guard interval > 0 else { return .disabled }

        guard let lastCheck else { return .checkNow }

        let intervalSeconds = TimeInterval(interval * 3600)
        let elapsed = now.timeIntervalSince(lastCheck)

        if elapsed >= intervalSeconds {
            return .checkNow
        } else {
            return .scheduleAfter(intervalSeconds - elapsed)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests/test_evaluate_nilLastCheck_returnsCheckNow`
Expected: PASS

- [ ] **Step 5: Write failing test for disabled (interval = 0)**

```swift
func test_evaluate_intervalZero_returnsDisabled() {
    let result = UpdateScheduler.evaluate(
        interval: 0,
        lastCheck: Date(),
        now: Date()
    )
    XCTAssertEqual(result, .disabled)
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests/test_evaluate_intervalZero_returnsDisabled`
Expected: PASS

- [ ] **Step 7: Write failing test for elapsed >= interval → checkNow**

```swift
func test_evaluate_elapsedExceedsInterval_returnsCheckNow() {
    let now = Date()
    let lastCheck = now.addingTimeInterval(-13 * 3600) // 13h ago, interval is 12h
    let result = UpdateScheduler.evaluate(
        interval: 12,
        lastCheck: lastCheck,
        now: now
    )
    XCTAssertEqual(result, .checkNow)
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests/test_evaluate_elapsedExceedsInterval_returnsCheckNow`
Expected: PASS

- [ ] **Step 9: Write failing test for elapsed < interval → scheduleAfter**

```swift
func test_evaluate_elapsedLessThanInterval_returnsScheduleAfter() {
    let now = Date()
    let lastCheck = now.addingTimeInterval(-6 * 3600) // 6h ago, interval is 12h
    let result = UpdateScheduler.evaluate(
        interval: 12,
        lastCheck: lastCheck,
        now: now
    )
    switch result {
    case .scheduleAfter(let delay):
        // Should be ~6 hours remaining
        XCTAssertEqual(delay, 6 * 3600, accuracy: 1.0)
    default:
        XCTFail("Expected .scheduleAfter, got \(result)")
    }
}
```

- [ ] **Step 10: Run test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests/test_evaluate_elapsedLessThanInterval_returnsScheduleAfter`
Expected: PASS

- [ ] **Step 11: Write failing test for exact interval boundary → checkNow**

```swift
func test_evaluate_elapsedExactlyAtInterval_returnsCheckNow() {
    let now = Date()
    let lastCheck = now.addingTimeInterval(-12 * 3600)
    let result = UpdateScheduler.evaluate(
        interval: 12,
        lastCheck: lastCheck,
        now: now
    )
    XCTAssertEqual(result, .checkNow)
}
```

- [ ] **Step 12: Run test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests/test_evaluate_elapsedExactlyAtInterval_returnsCheckNow`
Expected: PASS

- [ ] **Step 13: Run full UpdateScheduler test suite**

Run: `swift test --filter UpdateSchedulerTests`
Expected: All PASS

- [ ] **Step 14: Commit**

```bash
git add Sources/MLXManager/UpdateScheduler.swift Tests/MLXManagerTests/UpdateSchedulerTests.swift
git commit -m "feat: add UpdateScheduler with timer evaluation logic"
```

---

## Task 5: StatusBarController — "Restart to apply updates" menu item

**Files:**
- Modify: `Sources/MLXManager/StatusBarController.swift`
- Modify: `Tests/MLXManagerTests/StatusBarControllerTests.swift` (if exists, or the relevant test file)

- [ ] **Step 1: Find the existing StatusBarController tests**

Run: `swift test --filter StatusBarController 2>&1 | head -5` to confirm the test target name.

- [ ] **Step 2: Write failing test for restart menu item visibility**

```swift
func test_rebuildMenu_restartNeeded_showsRestartItem() {
    var settings = AppSettings()
    settings.restartNeeded = true
    let spy = SpyStatusBarView()
    let controller = StatusBarController(
        view: spy,
        presets: [],
        onStart: { _ in },
        onStop: {},
        settings: settings
    )

    controller.serverDidStart()

    let menuTitles = spy.lastMenuItems.map(\.title)
    XCTAssertTrue(menuTitles.contains("Restart to apply updates"))
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter <test_name>`
Expected: FAIL — no "Restart to apply updates" in menu items

- [ ] **Step 4: Add restart item to rebuildMenu**

In `StatusBarController.swift`, in `rebuildMenu(statusText:)`, add after the running server info block and before the preset section:

```swift
if currentSettings.restartNeeded && isServerRunning {
    items.append(StatusBarMenuItem(
        title: "Restart to apply updates",
        isEnabled: true,
        action: { [weak self] in self?.restartForUpdate() }
    ))
    items.append(StatusBarMenuItem(title: "-", isSeparator: true))
}
```

Add the action method:

```swift
private func restartForUpdate() {
    onStop()
    // The restart with current preset is handled by AppDelegate's
    // onProcessExit → auto-restart flow, or the user starts manually.
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter <test_name>`
Expected: PASS

- [ ] **Step 6: Write failing test for restart item hidden when not needed**

```swift
func test_rebuildMenu_restartNotNeeded_hidesRestartItem() {
    var settings = AppSettings()
    settings.restartNeeded = false
    let spy = SpyStatusBarView()
    let controller = StatusBarController(
        view: spy,
        presets: [],
        onStart: { _ in },
        onStop: {},
        settings: settings
    )

    controller.serverDidStart()

    let menuTitles = spy.lastMenuItems.map(\.title)
    XCTAssertFalse(menuTitles.contains("Restart to apply updates"))
}
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter <test_name>`
Expected: PASS

- [ ] **Step 8: Write failing test for restart item hidden when server offline**

```swift
func test_rebuildMenu_restartNeededButOffline_hidesRestartItem() {
    var settings = AppSettings()
    settings.restartNeeded = true
    let spy = SpyStatusBarView()
    let controller = StatusBarController(
        view: spy,
        presets: [],
        onStart: { _ in },
        onStop: {},
        settings: settings
    )

    // Don't call serverDidStart — stays offline

    let menuTitles = spy.lastMenuItems.map(\.title)
    XCTAssertFalse(menuTitles.contains("Restart to apply updates"))
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `swift test --filter <test_name>`
Expected: PASS

- [ ] **Step 10: Add `updateSettings` method to allow runtime settings updates**

The controller needs a way to receive updated settings (when `restartNeeded` changes). Add:

```swift
public func updateSettings(_ settings: AppSettings) {
    currentSettings = settings
    // Rebuild menu with current state
    switch lastDisplayState {
    case .offline: rebuildMenu(statusText: "Server: Offline")
    case .idle: rebuildMenu(statusText: "Server: Idle")
    case .processing(let f): rebuildMenu(statusText: "Processing: \(Int(f * 100))%")
    case .failed: rebuildMenu(statusText: "Server: Failed")
    }
}
```

- [ ] **Step 11: Run full StatusBarController test suite**

Run: `swift test --filter StatusBarControllerTests`
Expected: All PASS

- [ ] **Step 12: Commit**

```bash
git add Sources/MLXManager/StatusBarController.swift Tests/MLXManagerTests/StatusBarControllerTests.swift
git commit -m "feat: add 'Restart to apply updates' menu item when restartNeeded is true"
```

---

## Task 6: Integration — wire up in AppDelegate

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift` (or equivalent app-layer file)

This task is UI/integration wiring and is less TDD-driven. The logic has already been tested in Tasks 1-5.

- [ ] **Step 1: Read AppDelegate to understand the current wiring**

Read the file to find where `ServerCoordinator`, `StatusBarController`, and settings are initialized.

- [ ] **Step 2: Add update check on app launch**

In the app launch path (after settings are loaded), add:

```swift
private var updateTimer: Timer?
private var notificationTimer: Timer?
private lazy var packageChecker: PackageUpdateChecker? = {
    guard let uvPath = UVLocator().locate() else { return nil }
    return PackageUpdateChecker(uvPath: uvPath, runner: ProcessCommandRunner())
}()

private func scheduleUpdateCheck() {
    updateTimer?.invalidate()
    updateTimer = nil

    let action = UpdateScheduler.evaluate(
        interval: settings.updateCheckInterval,
        lastCheck: settings.lastUpdateCheck,
        now: Date()
    )

    switch action {
    case .checkNow:
        performUpdateCheck()
    case .scheduleAfter(let delay):
        updateTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performUpdateCheck()
        }
    case .disabled:
        break
    }
}
```

- [ ] **Step 3: Add the check + upgrade flow**

```swift
private func performUpdateCheck() {
    guard let checker = packageChecker else { return }

    DispatchQueue.global(qos: .utility).async { [weak self] in
        checker.checkForUpdates { result in
            guard let self else { return }

            DispatchQueue.main.async {
                self.settings.lastUpdateCheck = Date()
                self.saveSettings()

                if result.hasUpdates {
                    checker.upgrade { success in
                        DispatchQueue.main.async {
                            if success && self.isServerRunning {
                                self.settings.restartNeeded = true
                                self.saveSettings()
                                self.statusBarController.updateSettings(self.settings)
                                self.postRestartNotification()
                                self.startNotificationTimer()
                            }
                            self.scheduleUpdateCheck()
                        }
                    }
                } else {
                    self.scheduleUpdateCheck()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Add notification posting**

```swift
import UserNotifications

private func postRestartNotification() {
    let content = UNMutableNotificationContent()
    content.title = "MLX Manager"
    content.body = "MLX packages updated — restart server to apply"
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: "package-update-restart",
        content: content,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
}

private func startNotificationTimer() {
    notificationTimer?.invalidate()
    notificationTimer = Timer.scheduledTimer(withTimeInterval: 2 * 3600, repeats: true) { [weak self] _ in
        guard let self, self.settings.restartNeeded else {
            self?.notificationTimer?.invalidate()
            self?.notificationTimer = nil
            return
        }
        self.postRestartNotification()
    }
}
```

- [ ] **Step 5: Clear restartNeeded on server start**

In the server start path (where `serverDidStart` is called), add:

```swift
if settings.restartNeeded {
    settings.restartNeeded = false
    saveSettings()
    statusBarController.updateSettings(settings)
    notificationTimer?.invalidate()
    notificationTimer = nil
}
```

- [ ] **Step 6: Call `scheduleUpdateCheck()` on launch and when settings change**

Add `scheduleUpdateCheck()` at the end of `applicationDidFinishLaunching`. Also call it when the settings window saves (wherever settings are persisted after UI changes).

- [ ] **Step 7: Request notification permission on launch**

```swift
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
```

- [ ] **Step 8: Run full test suite**

Run: `swift test`
Expected: All PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "feat: wire up package auto-upgrade scheduling and notifications in AppDelegate"
```
