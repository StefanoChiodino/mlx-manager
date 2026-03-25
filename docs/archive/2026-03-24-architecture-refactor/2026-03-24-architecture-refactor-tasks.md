# Architecture Refactor — Task Specs for Cheaper Models

These tasks fix the structural weaknesses identified in the MLX Manager codebase. Each task is self-contained — give it to a model as-is. Tasks are ordered: **complete them sequentially** (each builds on the previous).

Follow the project's TDD rules in `AGENTS.md`: red-green-refactor, no production code without a failing test first.

---

## Task 1: Make StatusBarController.presets Mutable

### Problem

`StatusBarController.presets` is `let` (immutable). The only way to update presets is to destroy and recreate the entire controller. This forces a "nuclear rebuild" every time the settings window closes (`AppDelegate.swift:237-256`), which is the #1 source of recurring bugs.

### What to Do

1. Read these files first:
   - `Sources/MLXManager/StatusBarController.swift`
   - `Tests/MLXManagerTests/StatusBarControllerTests.swift`
   - `Tests/MLXManagerTests/StatusBarControllerNewTests.swift`

2. Change `private let presets: [ServerConfig]` to `private var presets: [ServerConfig]`

3. Add a public method `updatePresets(_ newPresets: [ServerConfig])` that:
   - Replaces the stored presets
   - Rebuilds the menu with the current status text (use the `running` flag to determine "Server: Idle" vs "Server: Offline")

4. Write tests first (TDD):
   - `test_updatePresets_replacesPresetsAndRebuildsMenu()` — call updatePresets with new presets, verify the menu items reflect the new preset names
   - `test_updatePresets_whileRunning_showsSwitchToHeader()` — call serverDidStart(), then updatePresets, verify menu shows "Switch to:" not "Start with:"
   - `test_updatePresets_whileOffline_showsStartWithHeader()` — verify menu shows "Start with:" after updatePresets when not running

5. Do NOT touch `AppDelegate.swift` in this task. That's Task 2.

### Verification

Run `swift test --filter StatusBarController` — all existing and new tests pass.

### Files to Modify
- `Sources/MLXManager/StatusBarController.swift`
- `Tests/MLXManagerTests/StatusBarControllerTests.swift` (or the NewTests file, whichever has the active tests)

---

## Task 2: Replace Nuclear Rebuild with In-Place Updates

### Problem

In `AppDelegate.swift`, the `showSettings()` method (line 237) defines a `rebuildController` closure that destroys and recreates `StatusBarController` and `StatusBarView` every time the settings window closes. This causes:
- The menu bar icon to flicker (new NSStatusItem created)
- All callback wiring to be re-done (miss one = silent failure)
- `recoverRunningServer` to be called unnecessarily (designed for app launch, not settings save)

### What to Do

1. Read these files first:
   - `Sources/MLXManagerApp/AppDelegate.swift` — focus on `showSettings()` (line 232+)
   - `Sources/MLXManager/StatusBarController.swift` — you need the `updatePresets()` method from Task 1
   - `Sources/MLXManagerApp/SettingsWindowController.swift` — understand the callback flow

2. In `AppDelegate.showSettings()`, replace the `rebuildController` closure with an `applyChanges` closure that:
   - Calls `self.settings = newSettings` and `self.saveSettings(newSettings)`
   - Calls `self.statusBarController.applySettings(newSettings)`
   - Calls `self.statusBarController.updatePresets(newPresets)`
   - Does NOT create a new StatusBarView or StatusBarController
   - Does NOT call `recoverRunningServer`

3. Wire both `onClose` and `onCancel` to this new `applyChanges` closure.

4. Keep the `onChange` handler as-is (it saves settings on every keystroke, which is fine).

5. The `settingsWindowController = nil` cleanup should happen in a `windowWillClose` handler or after the apply, not inside the closure.

### Verification

- Build the app (`make build` or `swift build`)
- Manual test: start a server, open settings, close settings — server should still show as running without the icon flickering
- The menu should reflect any preset changes made in settings

### Files to Modify
- `Sources/MLXManagerApp/AppDelegate.swift`

---

## Task 3: Eliminate Duplicated "running" State

### Problem

"Is the server running?" is tracked in three places that can diverge:
- `ServerManager.isRunning` — checks process handle or adoptedPID
- `ServerState.status` — state machine driven by log events
- `StatusBarController.running` — private bool toggled by serverDidStart/Stop

### What to Do

1. Read these files first:
   - `Sources/MLXManager/StatusBarController.swift`
   - `Sources/MLXManager/ServerState.swift`
   - `Sources/MLXManager/ServerManager.swift`
   - `Tests/MLXManagerTests/StatusBarControllerTests.swift`

2. Remove `private var running = false` from `StatusBarController`.

3. Replace all reads of `running` in StatusBarController with a check on the current display state. Add a private computed property:
   ```swift
   private var isServerRunning: Bool {
       // Derive from last known state instead of tracking separately
       lastDisplayState != .offline
   }
   ```
   Where `lastDisplayState` is a stored property updated whenever `view.updateState()` is called.

4. Remove the explicit `running = true` / `running = false` from `serverDidStart()` / `serverDidStop()`. These methods still call `view.updateState()` and `rebuildMenu()` — the `isServerRunning` computed property derives the answer.

5. Write tests first (TDD):
   - `test_isServerRunning_derivedFromDisplayState_notSeparateFlag()` — after calling `serverDidStart()`, verify menu shows running state; after `serverDidStop()`, verify offline state. The point is to confirm behavior is unchanged.
   - `test_update_processingState_menuShowsRunningItems()` — feed a processing ServerState via `update(state:)`, verify menu has "Stop" item (proving running is derived from state, not a separate flag)

### Verification

Run `swift test --filter StatusBarController` — all tests pass.

### Files to Modify
- `Sources/MLXManager/StatusBarController.swift`
- `Tests/MLXManagerTests/StatusBarControllerTests.swift` (or NewTests)

---

## Task 4: Extract ServerCoordinator

### Problem

`AppDelegate` manually orchestrates 5 subsystems through implicit call sequences. Starting a server requires 5 calls in exact order. Stopping requires 5 different calls. Missing one = inconsistent state. This should be one object's job.

### What to Do

1. Read these files first:
   - `Sources/MLXManagerApp/AppDelegate.swift` — focus on `startServer()`, `stopServer()`, `handleProcessExit()`, `recoverRunningServer()`, `startTailing()`, `handleLogEvent()`
   - `Sources/MLXManager/ServerManager.swift`
   - `Sources/MLXManager/ServerState.swift`
   - `Sources/MLXManager/LogTailer.swift`

2. Create `Sources/MLXManager/ServerCoordinator.swift` containing a new class `ServerCoordinator` that:
   - Owns a `ServerManager`, `ServerState`, and optional `LogTailer`
   - Has a `logPath: String` property
   - Exposes `start(config:)`, `stop()`, `adoptProcess(pid:port:)`
   - Internally manages the correct sequencing (create state, start tailer, etc.)
   - Publishes state changes via a callback: `var onStateChange: ((ServerState) -> Void)?`
   - Publishes log events via a callback: `var onLogEvent: ((LogEvent, String) -> Void)?` (event + raw line)
   - Publishes process exit via: `var onProcessExit: (() -> Void)?`
   - Has a read-only `var state: ServerState` property
   - Has a read-only `var isRunning: Bool` property

3. Create `Tests/MLXManagerTests/ServerCoordinatorTests.swift` with tests:
   - `test_start_setsStateToIdle_andStartsTailing()`
   - `test_stop_setsStateToOffline_andStopsTailing()`
   - `test_logEvent_updatesState_andNotifiesCallback()`
   - `test_processExit_setsStateToOffline()`
   - `test_start_whenAlreadyRunning_throwsAlreadyRunning()`

4. Use dependency injection for `ProcessLauncher` and a `LogTailer` factory so tests don't need real files/processes.

5. Do NOT modify AppDelegate yet — that's Task 5.

### Verification

Run `swift test --filter ServerCoordinator` — all new tests pass. Existing tests still pass.

### Files to Create
- `Sources/MLXManager/ServerCoordinator.swift`
- `Tests/MLXManagerTests/ServerCoordinatorTests.swift`

---

## Task 5: Wire ServerCoordinator into AppDelegate

### Problem

AppDelegate still has all the manual orchestration code. Now that ServerCoordinator exists (Task 4), AppDelegate should delegate to it.

### What to Do

1. Read these files first:
   - `Sources/MLXManagerApp/AppDelegate.swift`
   - `Sources/MLXManager/ServerCoordinator.swift` (from Task 4)

2. In AppDelegate:
   - Replace `serverManager`, `serverState`, and `logTailer` properties with a single `serverCoordinator` property
   - In `applicationDidFinishLaunching`, create the ServerCoordinator with the appropriate dependencies
   - Wire `serverCoordinator.onStateChange` to update `statusBarController`
   - Wire `serverCoordinator.onLogEvent` to update `logLines` and the status bar log line
   - Wire `serverCoordinator.onProcessExit` to call `statusBarController.serverDidStop()` and `resetSession()`
   - Replace `startServer(config:)` body with `serverCoordinator.start(config:)` + `statusBarController.serverDidStart()`
   - Replace `stopServer()` body with `serverCoordinator.stop()` + cleanup
   - Replace `handleProcessExit()` with the onProcessExit callback
   - Remove `startTailing()`, `handleLogEvent()`, `rawLine(for:)` — these now live in ServerCoordinator
   - Keep `loadHistoricalLog()` in AppDelegate for now (it's a UI concern — populating the log buffer)

3. Remove dead code: any private methods in AppDelegate that are now handled by ServerCoordinator.

### Verification

- `swift build` succeeds
- `swift test` — all tests pass
- Manual test: start server, observe progress, stop server — same behavior as before

### Files to Modify
- `Sources/MLXManagerApp/AppDelegate.swift`

---

## Task 6: Replace Silent Error Handling

### Problem

Multiple `try?` and empty `catch` blocks silently swallow errors, making debugging impossible.

### What to Do

1. Read `Sources/MLXManagerApp/AppDelegate.swift` (or wherever the coordinator now lives after Tasks 4-5).

2. Add a simple logging function at the top of the app layer:
   ```swift
   import os
   private let logger = Logger(subsystem: "com.mlx-manager", category: "app")
   ```

3. Replace each silent error handler:

   | Location | Current | Replace with |
   |----------|---------|-------------|
   | `adoptProcess` call in recovery | `try?` | `do/catch` that logs `.info` (expected when app owns the process) |
   | `startServer` catch block | `catch { // Already running — ignore }` | `catch { logger.warning("Start failed: \(error)") }` |
   | `loadPresets` | `try?` with fallback to `[]` | `do/catch` that logs `.error` and returns `[]` |
   | `loadSettings` | `try?` with fallback to defaults | `do/catch` that logs `.info` and returns defaults |
   | `saveSettings` | `try?` | `do/catch` that logs `.error` |

4. No tests needed for logging — this is observability, not behavior.

### Verification

- `swift build` succeeds
- Run the app, open Console.app, filter by "mlx-manager" — verify log messages appear for expected scenarios

### Files to Modify
- `Sources/MLXManagerApp/AppDelegate.swift`

---

## Task 7: Simplify Settings Callbacks

### Problem

`SettingsWindowController` has three callbacks (`onChange`, `onClose`, `onCancel`) plus a `closeCallbackFired` boolean guard to prevent double-firing. This is a state machine implemented with a flag.

### What to Do

1. Read these files first:
   - `Sources/MLXManagerApp/SettingsWindowController.swift`
   - `Sources/MLXManagerApp/AppDelegate.swift` — see how callbacks are wired

2. Replace the three callbacks with a single callback:
   ```swift
   var onDismiss: ((_ presets: [ServerConfig], _ settings: AppSettings, _ cancelled: Bool) -> Void)?
   ```

3. In `closeTapped()`: commit field editor, apply detail, call `onDismiss?(draftPresets, draftSettings, false)`, close window.

4. In `cancelTapped()`: revert to snapshot, call `onDismiss?(snapshotPresets, snapshotSettings, true)`, close window.

5. In `windowWillClose()`: if `onDismiss` hasn't been called yet (track with a `dismissed` bool), call `onDismiss?(draftPresets, draftSettings, false)`.

6. Remove `closeCallbackFired`. Replace with `dismissed` that serves the same purpose but with a clearer name.

7. Keep `onChange` as a separate callback — it fires on every keystroke for live persistence and is a different concern.

8. Update AppDelegate to wire the single `onDismiss` callback instead of three separate ones.

### Verification

- `swift build` succeeds
- Manual test: open settings, make changes, click Close — changes apply
- Manual test: open settings, make changes, click Cancel — changes revert
- Manual test: open settings, make changes, click window X button — changes apply (same as Close)

### Files to Modify
- `Sources/MLXManagerApp/SettingsWindowController.swift`
- `Sources/MLXManagerApp/AppDelegate.swift`

---

## Task 8: Backend-Aware Environment Bootstrap

### Problem

`AppDelegate.bootstrapEnvironmentIfNeeded()` only checks the first preset's backend: `let backend = presets.first?.serverType ?? .mlxLM`. If the user has VLM presets but their first preset is LM, the VLM venv is never bootstrapped.

### What to Do

1. Read these files first:
   - `Sources/MLXManagerApp/AppDelegate.swift` — `bootstrapEnvironmentIfNeeded()` method
   - `Sources/MLXManager/EnvironmentBootstrapper.swift`
   - `Sources/MLXManager/EnvironmentChecker.swift`

2. Change `bootstrapEnvironmentIfNeeded()` to check all unique backend types across all presets:
   ```swift
   private func bootstrapEnvironmentIfNeeded() {
       let presets = loadPresets()
       let checker = EnvironmentChecker()
       let backendsNeeded = Set(presets.map(\.serverType))
       let missing = backendsNeeded.filter { !checker.isReady(pythonPath: EnvironmentInstaller.pythonPath(for: $0)) }
       guard let first = missing.first else { return }
       // Bootstrap the first missing backend (could queue others, but one at a time is fine)
       statusBarController.environmentInstallStarted()
       let inst = EnvironmentInstaller(backend: first)
       inst.onComplete = { [weak self] _ in
           self?.statusBarController.environmentInstallFinished()
           self?.backgroundInstaller = nil
       }
       inst.install()
       backgroundInstaller = inst
   }
   ```

3. This is a small, focused change. No new tests needed (EnvironmentBootstrapper is already tested; this is app-layer wiring).

### Verification

- `swift build` succeeds
- If you have both LM and VLM presets, the app should detect and install whichever venv is missing

### Files to Modify
- `Sources/MLXManagerApp/AppDelegate.swift`
