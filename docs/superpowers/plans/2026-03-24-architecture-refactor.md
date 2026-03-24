# Architecture Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 8 structural weaknesses in MLX Manager — eliminating nuclear rebuilds, duplicated state, silent errors, and poorly bounded responsibilities.

**Architecture:** Tasks 1–3 are pure `MLXManager` library changes (testable in isolation). Tasks 4–5 introduce `ServerCoordinator` and wire it into `AppDelegate`. Tasks 6–8 are cleanup/polish passes on the app layer.

**Tech Stack:** Swift 5.9+, macOS 14+, XCTest + Swift Testing (both in use), SPM modules `MLXManager` (library) and `MLXManagerApp` (executable)

---

## Quick Reference

- Run library tests: `swift test --filter StatusBarController`
- Run all tests: `swift test`
- Build: `swift build` (or `make build` for the `.app`)
- Test file naming: `Sources/MLXManager/Foo.swift` → `Tests/MLXManagerTests/FooTests.swift`
- Mock infrastructure: `MockStatusBarView` lives in `Tests/MLXManagerTests/StatusBarControllerTests.swift` — reuse it
- Test framework: use **Swift Testing** (`@Test`, `#expect`) to match the existing test style in `StatusBarControllerTests.swift`

---

## Task 1: Make StatusBarController.presets Mutable

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 1

**Files:**
- Modify: `Sources/MLXManager/StatusBarController.swift`
- Modify: `Tests/MLXManagerTests/StatusBarControllerTests.swift`

### Context

`StatusBarController.presets` is `let`. Updating presets forces a full controller rebuild. After this task it will be `var` with a public `updatePresets(_:)` method that replaces presets and rebuilds the menu correctly.

The `running` flag (line 37) is still present in this task — Task 3 removes it. For now `updatePresets` uses `running` to pick the menu header.

---

- [ ] **Step 1.1: Write the first failing test — updatePresets replaces menu items**

Add to `Tests/MLXManagerTests/StatusBarControllerTests.swift`, inside the `@Suite("StatusBarController")` struct:

```swift
@Test("updatePresets replaces preset menu items")
func updatePresets_replacesPresetsAndRebuildsMenu() {
    let view = MockStatusBarView()
    let initial = ServerConfig.fixture(name: "Alpha")
    let controller = StatusBarController(view: view, presets: [initial], onStart: { _ in }, onStop: {})

    let updated = ServerConfig.fixture(name: "Beta")
    controller.updatePresets([updated])

    let titles = view.menuItems.map(\.title)
    #expect(titles.contains("Beta"))
    #expect(!titles.contains("Alpha"))
}
```

`ServerConfig.fixture` doesn't exist yet — add it as a test helper at the top of the test file (inside the file, not inside the `@Suite`):

```swift
extension ServerConfig {
    static func fixture(name: String = "Test", pythonPath: String = "/usr/bin/python3") -> ServerConfig {
        ServerConfig(
            name: name,
            pythonPath: pythonPath,
            model: "model",
            port: 8080,
            maxTokens: 2048,
            prefillStepSize: 512,
            promptCacheSize: 0,
            promptCacheBytes: 0,
            trustRemoteCode: false,
            enableThinking: false,
            extraArgs: "",
            serverType: .mlxLM,
            kvBits: nil,
            kvGroupSize: nil,
            maxKvSize: nil,
            quantizedKvStart: nil
        )
    }
}
```

> Note: Check `ServerConfig`'s actual initialiser signature in `Sources/MLXManager/ServerConfig.swift` before writing — use whatever fields exist. The fixture just needs to produce a valid `ServerConfig`.

- [ ] **Step 1.2: Run the test — confirm it fails to compile (updatePresets does not exist yet)**

```
swift test --filter "updatePresets_replacesPresetsAndRebuildsMenu"
```

Expected: compile error — `value of type 'StatusBarController' has no member 'updatePresets'`

- [ ] **Step 1.3: Write the second failing test — updatePresets while running shows "Switch to:"**

```swift
@Test("updatePresets while running shows Switch to header")
func updatePresets_whileRunning_showsSwitchToHeader() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    controller.serverDidStart()
    controller.updatePresets([ServerConfig.fixture(name: "GPU")])
    let titles = view.menuItems.map(\.title)
    #expect(titles.contains("Switch to:"))
    #expect(!titles.contains("Start with:"))
}
```

- [ ] **Step 1.4: Write the third failing test — updatePresets while offline shows "Start with:"**

```swift
@Test("updatePresets while offline shows Start with header")
func updatePresets_whileOffline_showsStartWithHeader() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    controller.updatePresets([ServerConfig.fixture(name: "CPU")])
    let titles = view.menuItems.map(\.title)
    #expect(titles.contains("Start with:"))
    #expect(!titles.contains("Switch to:"))
}
```

- [ ] **Step 1.5: Run all three new tests — confirm compile failure**

```
swift test --filter StatusBarController
```

Expected: compile error on `updatePresets`

- [ ] **Step 1.6: Change `let presets` to `var presets` and add `updatePresets`**

In `Sources/MLXManager/StatusBarController.swift`:

Change line 33:
```swift
private let presets: [ServerConfig]
```
to:
```swift
private var presets: [ServerConfig]
```

Add this public method after `applySettings(_:)` (around line 122):

```swift
/// Replace the stored presets and rebuild the menu.
public func updatePresets(_ newPresets: [ServerConfig]) {
    presets = newPresets
    rebuildMenu(statusText: running ? "Server: Idle" : "Server: Offline")
}
```

- [ ] **Step 1.7: Run the tests — all new tests and all existing tests must pass**

```
swift test --filter StatusBarController
```

Expected: all pass, no regressions.

- [ ] **Step 1.8: Commit**

```bash
git add Sources/MLXManager/StatusBarController.swift \
        Tests/MLXManagerTests/StatusBarControllerTests.swift
git commit -m "feat: add StatusBarController.updatePresets for in-place preset refresh"
```

---

## Task 2: Replace Nuclear Rebuild with In-Place Updates

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 2

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

### Context

`showSettings()` currently defines a `rebuildController` closure (lines 237–257) that destroys and recreates `StatusBarView` and `StatusBarController` on every settings close. This causes menu bar flicker, re-wires all callbacks, and calls `recoverRunningServer` unnecessarily.

Replace it with an `applyChanges` closure that calls `statusBarController.applySettings(_:)` and `statusBarController.updatePresets(_:)` in place. No new `StatusBarView` or `StatusBarController` is created. `recoverRunningServer` is not called.

The `settingsWindowController = nil` cleanup stays — it should remain in `windowWillClose` logic (it's already handled indirectly since `onClose`/`onCancel` is wired to `settingsWindowController = nil` — keep this placement inside the callback, not inside the closure itself).

No new unit tests for this task — the behaviour is verified by manual test (build and run).

---

- [ ] **Step 2.1: Replace `rebuildController` with `applyChanges` in `showSettings`**

In `Sources/MLXManagerApp/AppDelegate.swift`, replace the entire `rebuildController` closure (lines 237–257) with:

```swift
let applyChanges = { [weak self] (newPresets: [ServerConfig], newSettings: AppSettings) in
    guard let self else { return }
    self.settings = newSettings
    self.saveSettings(newSettings)
    self.statusBarController.applySettings(newSettings)
    self.statusBarController.updatePresets(newPresets)
    self.settingsWindowController = nil
}
```

Also update the callback wiring below it — change:

```swift
swc.onClose = rebuildController
swc.onCancel = rebuildController
```

to:

```swift
swc.onClose = applyChanges
swc.onCancel = applyChanges
```

Also update `onShowSettings` in `applicationDidFinishLaunching` — it currently captures `presets` as a snapshot. Change it to always load fresh presets at open time:

```swift
statusBarController.onShowSettings = { [weak self] in
    guard let self else { return }
    self.showSettings(presets: self.loadPresets())
}
```

(This replaces the existing `{ [weak self] in self?.showSettings(presets: presets) }` wiring on line 47.)

- [ ] **Step 2.2: Build**

```
swift build
```

Expected: builds with no errors.

- [ ] **Step 2.3: Manual smoke test**

Start the app, open Settings, make a preset change, click Close. Verify:
- Menu bar icon does not flicker
- Preset change is visible in menu
- If server was running before opening Settings, it still shows as running

- [ ] **Step 2.4: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "fix: replace nuclear StatusBarController rebuild with in-place applySettings+updatePresets"
```

---

## Task 3: Eliminate Duplicated "running" State

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 3

**Files:**
- Modify: `Sources/MLXManager/StatusBarController.swift`
- Modify: `Tests/MLXManagerTests/StatusBarControllerTests.swift`

### Context

`StatusBarController` has `private var running = false` toggled by `serverDidStart()` / `serverDidStop()`. Instead, derive running state from the last known display state (`lastDisplayState`), which is already set whenever `view.updateState()` is called.

The plan:
1. Add `private var lastDisplayState: StatusBarDisplayState = .offline`
2. Update `lastDisplayState` in every place that calls `view.updateState(_:)`
3. Add `private var isServerRunning: Bool { lastDisplayState != .offline }`
4. Replace all reads of `running` with `isServerRunning`
5. Remove `running = true` / `running = false` assignments
6. Remove `private var running = false`

---

- [ ] **Step 3.1: Write the first failing test — derived running state is correct after start/stop**

```swift
@Test("isServerRunning derived from display state after serverDidStart")
func isServerRunning_derivedFromDisplayState_afterStart() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    controller.serverDidStart()
    // Menu should show "Switch to:" header (implies running=true derived correctly)
    let titles = view.menuItems.map(\.title)
    #expect(titles.contains("Switch to:"))
}

@Test("isServerRunning derived from display state after serverDidStop")
func isServerRunning_derivedFromDisplayState_afterStop() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    controller.serverDidStart()
    controller.serverDidStop()
    let titles = view.menuItems.map(\.title)
    #expect(titles.contains("Start with:"))
    #expect(!titles.contains("Switch to:"))
}
```

- [ ] **Step 3.2: Write the second failing test — processing state shows running items**

```swift
@Test("processing ServerState causes menu to show Stop item")
func update_processingState_menuShowsStopItem() {
    let view = MockStatusBarView()
    let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
    controller.serverDidStart()
    var state = ServerState()
    state.serverStarted()
    // Feed a progress event so state becomes .processing
    state.handle(.progress(current: 10, total: 100, percentage: 10.0))
    controller.update(state: state)
    let titles = view.menuItems.map(\.title)
    #expect(titles.contains("Stop"))
}
```

- [ ] **Step 3.3: Run these tests — they should already pass (verifying existing behaviour)**

```
swift test --filter StatusBarController
```

Expected: all pass. These tests document the _current_ behaviour before refactoring.

- [ ] **Step 3.4: Refactor `StatusBarController` to derive running from display state**

In `Sources/MLXManager/StatusBarController.swift`:

Add after the `installingEnvironment` property (around line 39):

```swift
private var lastDisplayState: StatusBarDisplayState = .offline

private var isServerRunning: Bool {
    lastDisplayState != .offline
}
```

In every method that calls `view.updateState(...)`, also update `lastDisplayState`. There are four such call sites:

1. `init` → `view.updateState(.offline)` → add `lastDisplayState = .offline` before it
2. `serverDidStart()` → `view.updateState(.idle)` → add `lastDisplayState = .idle`
3. `serverDidStop()` → `view.updateState(.offline)` → add `lastDisplayState = .offline`
4. `update(state:)` → two branches: `.idle` path → add `lastDisplayState = .idle`; `.processing` path → add `lastDisplayState = .processing(fraction: fraction)`; `.offline` path → add `lastDisplayState = .offline`

Then:
- Replace all reads of `running` in `rebuildMenu`, `applySettings`, `environmentInstallFinished`, and `updatePresets` with `isServerRunning`
- Remove the `running = true` line in `serverDidStart()`
- Remove the `running = false` line in `serverDidStop()`
- Remove `private var running = false`

- [ ] **Step 3.5: Run all StatusBarController tests — must all pass**

```
swift test --filter StatusBarController
```

Expected: all pass, no regressions.

- [ ] **Step 3.6: Commit**

```bash
git add Sources/MLXManager/StatusBarController.swift \
        Tests/MLXManagerTests/StatusBarControllerTests.swift
git commit -m "refactor: derive StatusBarController.isServerRunning from display state, remove running flag"
```

---

## Task 4: Extract ServerCoordinator

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 4

**Files:**
- Create: `Sources/MLXManager/ServerCoordinator.swift`
- Create: `Tests/MLXManagerTests/ServerCoordinatorTests.swift`

### Context

`AppDelegate` currently orchestrates `ServerManager`, `ServerState`, and `LogTailer` manually through multi-step call sequences. `ServerCoordinator` will own all three and expose a simple API: `start(config:)`, `stop()`, `adoptProcess(pid:port:)`.

**Public interface:**

```swift
public final class ServerCoordinator {
    public var onStateChange: ((ServerState) -> Void)?
    public var onLogEvent: ((LogEvent, String) -> Void)?       // event + raw line
    public var onRequestCompleted: ((RequestRecord) -> Void)?  // fires once per completed request
    public var onProcessExit: (() -> Void)?

    public private(set) var state: ServerState
    public var isRunning: Bool { get }
    public var pid: Int32? { get }

    public init(
        logPath: String,
        launcher: ProcessLauncher,
        logTailerFactory: @escaping (String, @escaping (LogEvent) -> Void) -> any LogTailerProtocol
    )

    public func start(config: ServerConfig) throws
    public func stop()
    public func adoptProcess(pid: Int32, port: Int) throws
}
```

**Design notes:**
- `logTailerFactory` returns `any LogTailerProtocol` so tests can inject `MockLogTailer`
- `LogTailerProtocol` is defined in `ServerCoordinator.swift`; `LogTailer` retroactively conforms to it
- `rawLine(for:)` moves into `ServerCoordinator` (it's currently in `AppDelegate`)
- `onRequestCompleted` fires (and `state.clearCompletedRequest()` is called) inside `handleLogEvent` — the caller never clears it directly
- Do NOT modify `AppDelegate` yet — that's Task 5

---

- [ ] **Step 4.1: Write `test_start_setsStateToIdle_andStartsTailing`**

Create `Tests/MLXManagerTests/ServerCoordinatorTests.swift`:

```swift
import Testing
@testable import MLXManager

// MARK: - Test Doubles

final class MockLogTailer: LogTailerProtocol {
    private(set) var started = false
    private(set) var stopped = false
    var eventCallback: ((LogEvent) -> Void)?

    func start() { started = true }
    func stop() { stopped = true }
    func fire(_ event: LogEvent) { eventCallback?(event) }
}

final class MockProcessLauncherForCoordinator: ProcessLauncher {
    var shouldThrow: Error? = nil
    var launched = false
    var exitCallback: (() -> Void)?

    func launch(command: String, arguments: [String], logPath: String?, onExit: @escaping () -> Void) throws -> ProcessHandle {
        if let e = shouldThrow { throw e }
        launched = true
        exitCallback = onExit
        return MockProcessHandleForCoordinator()
    }
}

final class MockProcessHandleForCoordinator: ProcessHandle {
    var isRunning = true
    var processIdentifier: Int32 = 42
    func terminate() { isRunning = false }
}

@Suite("ServerCoordinator")
struct ServerCoordinatorTests {

    private func makeCoordinator(
        launcher: MockProcessLauncherForCoordinator = MockProcessLauncherForCoordinator(),
        tailer: MockLogTailer = MockLogTailer()
    ) -> (ServerCoordinator, MockLogTailer) {
        let t = tailer
        let coordinator = ServerCoordinator(
            logPath: "/tmp/test.log",
            launcher: launcher,
            logTailerFactory: { _, cb -> any LogTailerProtocol in
                t.eventCallback = cb
                return t
            }
        )
        return (coordinator, t)
    }
```

```swift
    @Test("start sets state to idle and starts tailing")
    func test_start_setsStateToIdle_andStartsTailing() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let tailer = MockLogTailer()
        let (coordinator, _) = makeCoordinator(launcher: launcher, tailer: tailer)

        try coordinator.start(config: ServerConfig.fixture())

        #expect(coordinator.isRunning)
        #expect(coordinator.state.status == .idle)
        #expect(tailer.started)
    }
```

- [ ] **Step 4.2: Run the test — confirm compile failure (ServerCoordinator does not exist)**

```
swift test --filter ServerCoordinator
```

Expected: compile error — `cannot find type 'ServerCoordinator'`

- [ ] **Step 4.3: Write `test_stop_setsStateToOffline_andStopsTailing`**

```swift
    @Test("stop sets state to offline and stops tailing")
    func test_stop_setsStateToOffline_andStopsTailing() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let tailer = MockLogTailer()
        let (coordinator, _) = makeCoordinator(launcher: launcher, tailer: tailer)

        try coordinator.start(config: ServerConfig.fixture())
        coordinator.stop()

        #expect(!coordinator.isRunning)
        #expect(coordinator.state.status == .offline)
        #expect(tailer.stopped)
    }
```

- [ ] **Step 4.4: Write `test_logEvent_updatesState_andNotifiesCallback`**

```swift
    @Test("log event updates state and notifies onStateChange callback")
    func test_logEvent_updatesState_andNotifiesCallback() throws {
        let tailer = MockLogTailer()
        let (coordinator, _) = makeCoordinator(tailer: tailer)
        try coordinator.start(config: ServerConfig.fixture())

        var receivedState: ServerState?
        coordinator.onStateChange = { receivedState = $0 }

        tailer.fire(.progress(current: 5, total: 100, percentage: 5.0))

        #expect(receivedState != nil)
        #expect(receivedState?.status == .processing)
    }
```

- [ ] **Step 4.5: Write `test_processExit_setsStateToOffline`**

```swift
    @Test("process exit fires onProcessExit and state becomes offline")
    func test_processExit_setsStateToOffline() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let (coordinator, _) = makeCoordinator(launcher: launcher)
        try coordinator.start(config: ServerConfig.fixture())

        var exitFired = false
        coordinator.onProcessExit = { exitFired = true }

        launcher.exitCallback?()

        #expect(exitFired)
        #expect(coordinator.state.status == .offline)
    }
```

- [ ] **Step 4.6: Write `test_start_whenAlreadyRunning_throwsAlreadyRunning`**

```swift
    @Test("start when already running throws alreadyRunning")
    func test_start_whenAlreadyRunning_throwsAlreadyRunning() throws {
        let (coordinator, _) = makeCoordinator()
        try coordinator.start(config: ServerConfig.fixture())
        #expect(throws: ServerError.alreadyRunning) {
            try coordinator.start(config: ServerConfig.fixture())
        }
    }
}
```

- [ ] **Step 4.7: Run all five tests — confirm compile failure**

```
swift test --filter ServerCoordinator
```

Expected: compile errors only (no `ServerCoordinator` type yet)

- [ ] **Step 4.8: Implement `ServerCoordinator`**

Create `Sources/MLXManager/ServerCoordinator.swift`:

```swift
import Foundation

/// Protocol so LogTailer can be replaced by a mock in tests.
public protocol LogTailerProtocol {
    func start()
    func stop()
}

extension LogTailer: LogTailerProtocol {}

/// Coordinates ServerManager, ServerState, and LogTailer into a single unit.
public final class ServerCoordinator {
    private let serverManager: ServerManager
    private var serverState: ServerState = ServerState()
    private var logTailer: (any LogTailerProtocol)?
    private let logPath: String
    private let logTailerFactory: (String, @escaping (LogEvent) -> Void) -> any LogTailerProtocol

    public var onStateChange: ((ServerState) -> Void)?
    public var onLogEvent: ((LogEvent, String) -> Void)?
    public var onRequestCompleted: ((RequestRecord) -> Void)?
    public var onProcessExit: (() -> Void)?

    public private(set) var state: ServerState = ServerState()

    public var isRunning: Bool { serverManager.isRunning }
    public var pid: Int32? { serverManager.pid }

    public init(
        logPath: String,
        launcher: ProcessLauncher,
        logTailerFactory: @escaping (String, @escaping (LogEvent) -> Void) -> any LogTailerProtocol
    ) {
        self.logPath = logPath
        self.logTailerFactory = logTailerFactory
        self.serverManager = ServerManager(launcher: launcher)
        self.serverManager.logPath = logPath
        self.serverManager.onExit = { [weak self] in
            self?.handleProcessExit()
        }
    }

    public func start(config: ServerConfig) throws {
        try serverManager.start(config: config)
        state = ServerState()
        state.serverStarted()
        onStateChange?(state)
        startTailing()
    }

    public func stop() {
        logTailer?.stop()
        logTailer = nil
        serverManager.stop()
        state.serverStopped()
        onStateChange?(state)
    }

    public func adoptProcess(pid: Int32, port: Int = 8080) throws {
        try serverManager.adoptProcess(pid: pid, port: port)
        state = ServerState()
        state.serverStarted()
        onStateChange?(state)
        startTailing()
    }

    // MARK: - Private

    private func startTailing() {
        logTailer?.stop()
        logTailer = logTailerFactory(logPath) { [weak self] event in
            self?.handleLogEvent(event)
        }
        logTailer?.start()
    }

    private func handleLogEvent(_ event: LogEvent) {
        let line = rawLine(for: event)
        onLogEvent?(event, line)
        state.handle(event)
        onStateChange?(state)
        if let record = state.completedRequest {
            onRequestCompleted?(record)
            state.clearCompletedRequest()
        }
    }

    private func handleProcessExit() {
        logTailer?.stop()
        logTailer = nil
        state.serverStopped()
        onProcessExit?()
    }

    private func rawLine(for event: LogEvent) -> String {
        switch event {
        case let .progress(current, total, _):
            return "Prompt processing progress: \(current)/\(total)"
        case let .kvCaches(gpu, tokens):
            return String(format: "KV Caches: ... %.2f GB, latest user cache %d tokens", gpu, tokens)
        case .httpCompletion:
            return "POST /v1/chat/completions HTTP/1.1\" 200"
        }
    }
}
```

> **Note on `LogEvent` cases:** Check `Sources/MLXManager/LogParser.swift` or `ServerState.swift` for the actual `LogEvent` enum cases and their associated values. Match `rawLine(for:)` to match the cases already used in `AppDelegate.rawLine(for:)` (lines 190–198 of AppDelegate.swift).

- [ ] **Step 4.9: Run all five coordinator tests — all must pass**

```
swift test --filter ServerCoordinator
```

Expected: all 5 pass.

- [ ] **Step 4.10: Run full test suite — no regressions**

```
swift test
```

Expected: all pass.

- [ ] **Step 4.11: Commit**

```bash
git add Sources/MLXManager/ServerCoordinator.swift \
        Tests/MLXManagerTests/ServerCoordinatorTests.swift
git commit -m "feat: extract ServerCoordinator to encapsulate ServerManager+ServerState+LogTailer"
```

---

## Task 5: Wire ServerCoordinator into AppDelegate

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 5

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

### Context

Replace the three separate properties `serverManager`, `serverState`, `logTailer` with a single `serverCoordinator: ServerCoordinator`. Wire its callbacks. Remove the private methods that `ServerCoordinator` now handles internally (`startTailing`, `handleLogEvent`, `rawLine`).

`loadHistoricalLog()` stays in `AppDelegate` — it populates the log buffer on startup and is a UI concern.

---

- [ ] **Step 5.1: Replace server-related properties**

In `Sources/MLXManagerApp/AppDelegate.swift`:

Remove:
```swift
private var serverManager: ServerManager!
private var logTailer: LogTailer?
private var serverState = ServerState()
```

Add:
```swift
private var serverCoordinator: ServerCoordinator!
```

- [ ] **Step 5.2: Update `applicationDidFinishLaunching` to create and wire `ServerCoordinator`**

Replace the `serverManager = ...` setup block with:

```swift
serverCoordinator = ServerCoordinator(
    logPath: logPath,
    launcher: RealProcessLauncher(),
    logTailerFactory: { path, onEvent in
        LogTailer(
            path: path,
            fileHandleFactory: { p in
                guard let fh = FileHandle(forReadingAtPath: p) else { return nil }
                return RealFileHandle(fh)
            },
            watcher: RealFileWatcher(),
            onEvent: onEvent
        )
    }
)

serverCoordinator.onStateChange = { [weak self] state in
    guard let self else { return }
    self.statusBarController.update(state: state)
}

serverCoordinator.onRequestCompleted = { [weak self] record in
    guard let self else { return }
    self.requestHistory.append(record)
    if self.requestHistory.count > 500 { self.requestHistory.removeFirst() }
}

serverCoordinator.onLogEvent = { [weak self] event, line in
    guard let self else { return }
    let kind = LogLineKind(event)
    self.logLines.append((line, kind))
    if self.logLines.count > 10_000 { self.logLines.removeFirst() }
    if self.settings.showLastLogLine {
        self.statusBarController.updateLogLine(LogLineStripper.strip(line))
    }
}

serverCoordinator.onProcessExit = { [weak self] in
    guard let self else { return }
    self.stopRAMPolling()
    self.statusBarController.serverDidStop()
    self.resetSession()
}
```

> **Note on `state.completedRequest`:** Check whether `ServerState.completedRequest` and `clearCompletedRequest()` are public and whether the `onStateChange` callback is the right place for this. If `ServerCoordinator` exposes `onLogEvent` with the event, and the `ServerState` inside coordinator is updated, you may need to check the completed request after each `handleLogEvent` call inside `ServerCoordinator`. Consider adding an `onRequestCompleted: ((RequestRecord) -> Void)?` callback to `ServerCoordinator` if needed — match the actual `ServerState` API.

- [ ] **Step 5.3: Update `startServer(config:)`**

Replace the body with:

```swift
private func startServer(config: ServerConfig) {
    let resolvedConfig = config.withResolvedPythonPath()
    do {
        try serverCoordinator.start(config: resolvedConfig)
        loadHistoricalLog()
        statusBarController.serverDidStart()
        if settings.ramGraphEnabled, let pid = serverCoordinator.pid {
            startRAMPolling(pid: pid)
        }
    } catch {
        // Already running — ignore
    }
}
```

> `serverCoordinator.pid` — check whether `ServerCoordinator` needs a `var pid: Int32?` property. Add it if not already exposed, delegating to `serverManager.pid`.

- [ ] **Step 5.4: Update `stopServer()`**

```swift
private func stopServer() {
    stopRAMPolling()
    serverCoordinator.stop()
    statusBarController.serverDidStop()
    resetSession()
}
```

- [ ] **Step 5.5: Update `recoverRunningServer`**

```swift
private func recoverRunningServer(presets: [ServerConfig]) {
    let scanner = ProcessScanner(
        pidLister: SystemPIDLister(),
        argvReader: SystemProcessArgvReader()
    )
    guard let found = scanner.findAnyServer() else { return }
    try? serverCoordinator.adoptProcess(pid: found.pid, port: found.port)
    loadHistoricalLog()
    statusBarController.serverDidStart()
    if settings.ramGraphEnabled {
        startRAMPolling(pid: found.pid)
    }
}
```

- [ ] **Step 5.6: Remove dead methods**

Remove from `AppDelegate`:
- `startTailing()` — now in `ServerCoordinator`
- `handleLogEvent(_:)` — now in `ServerCoordinator`
- `rawLine(for:)` — now in `ServerCoordinator`
- `handleProcessExit()` — now wired via `serverCoordinator.onProcessExit`

Keep:
- `loadHistoricalLog()` — UI concern, stays in `AppDelegate`

- [ ] **Step 5.7: Build**

```
swift build
```

Fix any remaining compile errors.

- [ ] **Step 5.8: Run full test suite**

```
swift test
```

Expected: all pass.

- [ ] **Step 5.9: Manual smoke test**

Start the app. Start a server. Observe progress in the menu bar. Stop the server. Verify same behaviour as before.

- [ ] **Step 5.10: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "refactor: wire ServerCoordinator into AppDelegate, remove manual server orchestration"
```

---

## Task 6: Replace Silent Error Handling

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 6

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

No new tests — this is observability, not behaviour change.

---

- [ ] **Step 6.1: Add `os.Logger` import and logger constant**

At the top of `Sources/MLXManagerApp/AppDelegate.swift`, add:

```swift
import os

private let logger = Logger(subsystem: "com.mlx-manager", category: "app")
```

- [ ] **Step 6.2: Replace `try?` in `recoverRunningServer` (`adoptProcess` call)**

Change:
```swift
try? serverCoordinator.adoptProcess(pid: found.pid, port: found.port)
```
to:
```swift
do {
    try serverCoordinator.adoptProcess(pid: found.pid, port: found.port)
} catch {
    logger.info("adoptProcess skipped: \(error) — app likely owns the process")
}
```

- [ ] **Step 6.3: Replace silent catch in `startServer`**

Change:
```swift
} catch {
    // Already running — ignore
}
```
to:
```swift
} catch {
    logger.warning("startServer failed: \(error)")
}
```

- [ ] **Step 6.4: Replace `try?` in `loadPresets`**

In the `loadPresets()` method, change the bundled YAML loading:

```swift
// Before
guard let url = bundledPresetsURL(),
      let yaml = try? String(contentsOf: url, encoding: .utf8),
      let presets = try? ConfigLoader.load(yaml: yaml) else {
    return []
}
```

to:

```swift
guard let url = bundledPresetsURL() else { return [] }
do {
    let yaml = try String(contentsOf: url, encoding: .utf8)
    let presets = try ConfigLoader.load(yaml: yaml)
    return presets.map { $0.withResolvedPythonPath() }
} catch {
    logger.error("loadPresets failed: \(error)")
    return []
}
```

Also for `UserPresetStore.load`:

```swift
// Before
if let presets = try? UserPresetStore.load(from: UserPresetStore.defaultURL) {
```

to:

```swift
do {
    let presets = try UserPresetStore.load(from: UserPresetStore.defaultURL)
    return presets.map { $0.withResolvedPythonPath() }
} catch {
    logger.error("loadPresets (user file) failed: \(error)")
    // Fall through to bundled presets
}
```

(Restructure the function appropriately.)

- [ ] **Step 6.5: Replace `try?` in `loadSettings`**

```swift
private func loadSettings() -> AppSettings {
    do {
        let data = try Data(contentsOf: settingsURL)
        return try JSONDecoder().decode(AppSettings.self, from: data)
    } catch {
        logger.info("loadSettings using defaults: \(error)")
        return AppSettings()
    }
}
```

- [ ] **Step 6.6: Replace `try?` in `saveSettings`**

```swift
private func saveSettings(_ s: AppSettings) {
    do {
        let data = try JSONEncoder().encode(s)
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsURL)
    } catch {
        logger.error("saveSettings failed: \(error)")
    }
}
```

- [ ] **Step 6.7: Build**

```
swift build
```

Expected: no errors.

- [ ] **Step 6.8: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "fix: replace silent try? error swallowing with os.Logger logging in AppDelegate"
```

---

## Task 7: Simplify Settings Callbacks

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 7

**Files:**
- Modify: `Sources/MLXManagerApp/SettingsWindowController.swift`
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

### Context

Replace three callbacks (`onClose`, `onCancel`, `closeCallbackFired`) with a single `onDismiss` callback plus a cleaner `dismissed` guard. `onChange` stays separate (different concern: live keystroke persistence).

---

- [ ] **Step 7.1: Replace callbacks in `SettingsWindowController`**

In `Sources/MLXManagerApp/SettingsWindowController.swift`, replace:

```swift
var onChange: (([ServerConfig], AppSettings) -> Void)?
var onClose: (([ServerConfig], AppSettings) -> Void)?
var onCancel: (([ServerConfig], AppSettings) -> Void)?
private var closeCallbackFired = false
```

with:

```swift
var onChange: (([ServerConfig], AppSettings) -> Void)?
var onDismiss: ((_ presets: [ServerConfig], _ settings: AppSettings, _ cancelled: Bool) -> Void)?
private var dismissed = false
```

- [ ] **Step 7.2: Update `closeTapped()`**

Replace the body with:

```swift
@objc private func closeTapped() {
    window?.makeFirstResponder(nil)
    applyDetail()
    dismissed = true
    onDismiss?(draftPresets, draftSettings, false)
    window?.close()
}
```

- [ ] **Step 7.3: Update `cancelTapped()`**

Replace the body with:

```swift
@objc private func cancelTapped() {
    draftPresets = snapshotPresets
    draftSettings = snapshotSettings
    if snapshotSettings.startAtLogin != (startAtLoginCheckbox.state == .on) {
        if snapshotSettings.startAtLogin { LoginItemManager.enable() } else { LoginItemManager.disable() }
    }
    try? UserPresetStore.save(snapshotPresets, to: UserPresetStore.defaultURL)
    dismissed = true
    onDismiss?(snapshotPresets, snapshotSettings, true)
    window?.close()
}
```

- [ ] **Step 7.4: Update `windowWillClose`**

Replace:

```swift
func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    if !closeCallbackFired {
        onClose?(draftPresets, draftSettings)
    }
}
```

with:

```swift
func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    if !dismissed {
        onDismiss?(draftPresets, draftSettings, false)
    }
}
```

- [ ] **Step 7.5: Update AppDelegate to wire `onDismiss`**

In `Sources/MLXManagerApp/AppDelegate.swift`, inside `showSettings()`, replace the two wiring lines:

```swift
swc.onClose = applyChanges
swc.onCancel = applyChanges
```

with:

```swift
swc.onDismiss = { [weak self] newPresets, newSettings, cancelled in
    guard let self else { return }
    self.settings = newSettings
    self.saveSettings(newSettings)
    self.statusBarController.applySettings(newSettings)
    self.statusBarController.updatePresets(newPresets)
    self.settingsWindowController = nil
}
```

(The `cancelled` flag is available for future use — currently both paths apply changes, which matches the old behaviour where `onCancel` also called `rebuildController`.)

- [ ] **Step 7.6: Build**

```
swift build
```

Fix any compile errors.

- [ ] **Step 7.7: Manual smoke test**

- Open Settings, change a preset, click Close → changes apply
- Open Settings, change a preset, click Cancel → changes revert
- Open Settings, change a preset, click × → changes apply (same as Close)

- [ ] **Step 7.8: Commit**

```bash
git add Sources/MLXManagerApp/SettingsWindowController.swift \
        Sources/MLXManagerApp/AppDelegate.swift
git commit -m "refactor: replace onClose/onCancel/closeCallbackFired with single onDismiss callback"
```

---

## Task 8: Backend-Aware Environment Bootstrap

**Spec:** `docs/superpowers/specs/2026-03-24-architecture-refactor-tasks.md` §Task 8

**Files:**
- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

### Context

`bootstrapEnvironmentIfNeeded()` currently only checks `presets.first?.serverType`. Replace with a check across all unique backend types — bootstrap the first missing one.

No new tests needed (app-layer wiring; `EnvironmentBootstrapper` already tested).

---

- [ ] **Step 8.1: Replace `bootstrapEnvironmentIfNeeded`**

In `Sources/MLXManagerApp/AppDelegate.swift`, replace the entire method:

```swift
private func bootstrapEnvironmentIfNeeded() {
    let presets = loadPresets()
    let checker = EnvironmentChecker()
    let backendsNeeded = Set(presets.map(\.serverType))
    let missing = backendsNeeded.filter { !checker.isReady(pythonPath: EnvironmentInstaller.pythonPath(for: $0)) }
    guard let first = missing.first else { return }
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

> **Note:** Check that `EnvironmentInstaller.pythonPath(for:)` and `EnvironmentChecker.isReady(pythonPath:)` exist with these exact signatures in `Sources/MLXManager/EnvironmentInstaller.swift` and `Sources/MLXManager/EnvironmentChecker.swift` before writing this. Adjust signatures if needed.

- [ ] **Step 8.2: Build**

```
swift build
```

Expected: no errors.

- [ ] **Step 8.3: Commit**

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "fix: bootstrap all unique backend envs, not just first preset's backend"
```

---

## Completion Checklist

- [ ] `swift test` — all tests pass
- [ ] `swift build` — clean build
- [ ] Manual smoke: start server, open settings, change preset, close — no flicker, changes apply
- [ ] Manual smoke: start server, stop server — state updates correctly
- [ ] Console.app shows `com.mlx-manager` log entries for expected error scenarios
