# Tasks: 008-ui-windows

Each task = one RED test confirmed failing, then GREEN implementation.
Window controllers (pure AppKit) have no unit tests — verified by build + manual smoke.

---

## A. AppSettings

- [x] **RED** `test_appSettings_defaultValues` — `AppSettings` doesn't exist; fails to compile
- [x] **GREEN** create `AppSettings.swift` with `AppSettings` struct, defaults `false`, `5`
- Note: `ProgressStyle` enum was dropped — 009-progress-arc replaced bar/pie with native `ArcProgressView`

---

## B. RequestRecord & ServerState extension

- [x] **RED** `test_requestRecord_duration` — `RequestRecord` doesn't exist; fails to compile
- [x] **GREEN** create `RequestRecord.swift`

- [x] **RED** `test_serverState_completedRequest_setOnKVCompletion` — `ServerState.completedRequest` doesn't exist; fails to compile
- [x] **GREEN** add `requestStartedAt`, `completedRequest`, `clearCompletedRequest()` to `ServerState`

- [x] **RED** `test_serverState_completedRequest_setOnHTTPCompletion` — verifies `.httpCompletion` also populates `completedRequest`
- [x] **GREEN** wire `.httpCompletion` path in `ServerState.handle`

- [x] **RED** `test_serverState_completedRequest_nilIfNoProgress` — completion signal with no prior progress → `completedRequest` is nil (tokens = 0 edge case: still records with tokens from KV line)
- [x] **GREEN** guard `requestStartedAt != nil` before emitting record

- [x] **RED** `test_serverState_clearCompletedRequest` — after `clearCompletedRequest()`, `completedRequest` is nil
- [x] **GREEN** trivial nil assignment

---

## C. ServerConfig Codable

- [x] **RED** `test_serverConfig_encodeDecode` — `ServerConfig` has no `Codable`; fails to compile
- [x] **GREEN** add `Codable` to `ServerConfig`

---

## D. UserPresetStore

- [x] **RED** `test_userPresetStore_saveAndLoad` — `UserPresetStore` doesn't exist; fails to compile
- [x] **GREEN** create `UserPresetStore.swift`: `save(_:)` encodes to YAML via Yams, writes to `userFileURL`; `load()` reads user file if present else bundled

- [x] **RED** `test_userPresetStore_loadFallsBackToBundled` — delete user file; `load()` returns bundled presets (4 items)
- [x] **GREEN** already handled by `load()` fallback logic

---

## E. RAMPoller

- [x] **RED** `test_ramPoller_emitsSample` — `RAMPoller` doesn't exist; fails to compile
- [x] **GREEN** create `RAMPoller.swift` with `PIDInfoProvider` protocol; real impl uses `proc_pidinfo`; test impl returns fixed bytes; timer fires once in test with 0.01s interval → asserts `onSample` called with expected GB

---

## F0. StatusBarController — menu UX

- [x] **RED** `test_offlineMenuShowsStartWithHeader` — no "Start with:" header exists; fails to find item
- [x] **GREEN** insert disabled "Start with:" / "Switch to:" header before preset items
- [x] **RED** `test_startWithHeaderIsDisabled` — header item enabled; fails
- [x] **GREEN** `isEnabled: false` on header item
- [x] **RED** `test_runningMenuShowsSwitchToHeader` — running state missing "Switch to:"; fails
- [x] **GREEN** branch on `running` flag for header label
- [x] **RED** `test_stopAbsentWhenOffline` — "Stop" present when offline; fails
- [x] **GREEN** wrap Stop item in `if running { }` — absent when offline
- [x] **RED** `test_presetWithMissingPythonIsDisabled` — no `fileExists` param; compile error
- [x] **GREEN** inject `fileExists: (String) -> Bool`; disabled + "(env missing)" suffix when path absent
- [x] **RED** `test_presetWithValidPythonIsEnabled` — verify enabled path with `fileExists: { _ in true }`
- [x] **GREEN** covered by same implementation
- [x] **FIX** `StatusBarView.buildMenu` — `NSMenuItem` ignores `isEnabled` when action is set; only assign action/target when `isEnabled && action != nil`
- [x] **FIX** `ServerConfig` — add explicit `public init` so memberwise init is accessible across module boundary after `Codable` conformance added

---

## F. StatusBarController — status text & progress style

Superseded by 009-progress-arc: native `ArcProgressView` + `StatusBarDisplayState` replaced the
glyph-based progress bar and pie styles. The `.bar`/`.pie` `ProgressStyle` toggle no longer exists.

What was implemented:

- [x] Menu contains "Show Log", "Request History", "Settings…", conditional "RAM Graph"
- [x] Arc-based progress rendering with percentage label (via 009)

What was dropped (superseded by 009):

- ~~`test_statusBarController_statusText_offline`~~ — status text menu item not added; state is conveyed by the arc icon
- ~~`test_statusBarController_statusText_processing`~~ — same
- ~~`test_statusBarController_progressBar_includesPercentage`~~ — replaced by `ArcProgressView` percentage label
- ~~`test_statusBarController_progressStyle_pie`~~ — `ProgressStyle` enum removed entirely

---

## G. Bundled presets.yaml

- [x] Update `pythonPath` in `Sources/MLXManagerApp/presets.yaml` to `~/.mlx-manager/venv/bin/python` for all four presets
- [x] Verify `swift test` still green (no test changes needed — existing test checks non-empty pythonPath)

---

## H. Window controllers (build-only, no unit tests)

- [x] Create `LogWindowController.swift` — NSWindow + NSTextView, `append(line:kind:)`, `clear()`
- [x] Create `HistoryWindowController.swift` — NSWindow + `HistoryChartView`, `update(records:)`
- [x] Create `RAMGraphWindowController.swift` — NSWindow + `RAMGraphView`, `update(samples:)`
- [x] Create `SettingsWindowController.swift` — NSWindow + NSTabView (Presets + General tabs)
- [x] Create `EnvironmentInstaller.swift` — thin adapter over `EnvironmentBootstrapper` (updated by 011-uv-env)
- [x] Verify `swift build` clean

---

## I. AppDelegate wiring

- [x] Add `logLines`, `requestHistory`, `ramSamples`, `settings` properties
- [x] Extend `handleLogEvent` to: append to log buffer → feed `LogWindowController`; drain `completedRequest` → history
- [x] Start/stop `RAMPoller` with server; feed `RAMGraphWindowController`
- [x] Add `onShowLog`, `onShowHistory`, `onShowRAMGraph`, `onShowSettings` closures wired into `StatusBarController`
- [x] Load `AppSettings` from `~/.config/mlx-manager/settings.json` on launch; pass to `StatusBarController`
- [x] Use `UserPresetStore.load()` instead of `Bundle.module` directly
- [x] Verify `swift build` and manual smoke test

---

## Done

- [x] All tests green — run `swift test`
- [x] `swift build` produces a runnable app
