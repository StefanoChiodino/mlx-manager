# Tasks: 008-ui-windows

Each task = one RED test confirmed failing, then GREEN implementation.
Window controllers (pure AppKit) have no unit tests — verified by build + manual smoke.

---

## A. AppSettings

- [ ] **RED** `test_appSettings_defaultValues` — `AppSettings` doesn't exist; fails to compile
- [ ] **GREEN** create `AppSettings.swift` with `ProgressStyle` enum and `AppSettings` struct, defaults `.bar`, `false`, `5`

---

## B. RequestRecord & ServerState extension

- [ ] **RED** `test_requestRecord_duration` — `RequestRecord` doesn't exist; fails to compile
- [ ] **GREEN** create `RequestRecord.swift`

- [ ] **RED** `test_serverState_completedRequest_setOnKVCompletion` — `ServerState.completedRequest` doesn't exist; fails to compile
- [ ] **GREEN** add `requestStartedAt`, `completedRequest`, `clearCompletedRequest()` to `ServerState`

- [ ] **RED** `test_serverState_completedRequest_setOnHTTPCompletion` — verifies `.httpCompletion` also populates `completedRequest`
- [ ] **GREEN** wire `.httpCompletion` path in `ServerState.handle`

- [ ] **RED** `test_serverState_completedRequest_nilIfNoProgress` — completion signal with no prior progress → `completedRequest` is nil (tokens = 0 edge case: still records with tokens from KV line)
- [ ] **GREEN** guard `requestStartedAt != nil` before emitting record

- [ ] **RED** `test_serverState_clearCompletedRequest` — after `clearCompletedRequest()`, `completedRequest` is nil
- [ ] **GREEN** trivial nil assignment

---

## C. ServerConfig Codable

- [ ] **RED** `test_serverConfig_encodeDecode` — `ServerConfig` has no `Codable`; fails to compile
- [ ] **GREEN** add `Codable` to `ServerConfig`

---

## D. UserPresetStore

- [ ] **RED** `test_userPresetStore_saveAndLoad` — `UserPresetStore` doesn't exist; fails to compile
- [ ] **GREEN** create `UserPresetStore.swift`: `save(_:)` encodes to YAML via Yams, writes to `userFileURL`; `load()` reads user file if present else bundled

- [ ] **RED** `test_userPresetStore_loadFallsBackToBundled` — delete user file; `load()` returns bundled presets (4 items)
- [ ] **GREEN** already handled by `load()` fallback logic

---

## E. RAMPoller

- [ ] **RED** `test_ramPoller_emitsSample` — `RAMPoller` doesn't exist; fails to compile
- [ ] **GREEN** create `RAMPoller.swift` with `PIDInfoProvider` protocol; real impl uses `proc_pidinfo`; test impl returns fixed bytes; timer fires once in test with 0.01s interval → asserts `onSample` called with expected GB

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

- [ ] **RED** `test_statusBarController_statusText_offline` — `StatusBarController.update(state:settings:)` doesn't exist; fails to compile
- [ ] **GREEN** add `settings: AppSettings` param to `update`; render status text item as first menu item (disabled)

- [ ] **RED** `test_statusBarController_statusText_processing` — verifies `"27,611 / 41,061  (67%)"` format in menu item title
- [ ] **GREEN** implement status text formatting in `StatusBarController`

- [ ] **RED** `test_statusBarController_progressBar_includesPercentage` — icon title contains `" 32%"` suffix
- [ ] **GREEN** append `" \(pct)%"` to `progressBar` output

- [ ] **RED** `test_statusBarController_progressStyle_pie` — with `.pie` style, icon title is a pie glyph not a block bar
- [ ] **GREEN** add `pieGlyph(fraction:)` helper; branch on `settings.progressStyle`

- [ ] **RED** `test_statusBarController_menuContainsLogItem` — menu items include `"Show Log"`
- [ ] **GREEN** add "Show Log", "Request History", "Settings…" items to `rebuildMenu`; "RAM Graph" only when `settings.ramGraphEnabled`

---

## G. Bundled presets.yaml

- [ ] Update `pythonPath` in `Sources/MLXManagerApp/presets.yaml` to `~/.mlx-manager/venv/bin/python` for all four presets
- [ ] Verify `swift test` still green (no test changes needed — existing test checks non-empty pythonPath)

---

## H. Window controllers (build-only, no unit tests)

- [ ] Create `LogWindowController.swift` — NSWindow + NSTextView, `append(line:kind:)`, `clear()`
- [ ] Create `HistoryWindowController.swift` — NSWindow + `HistoryChartView`, `update(records:)`
- [ ] Create `RAMGraphWindowController.swift` — NSWindow + `RAMGraphView`, `update(samples:)`
- [ ] Create `SettingsWindowController.swift` — NSWindow + NSTabView (Presets + General tabs)
- [ ] Create `EnvironmentInstaller.swift` — venv + pip, streaming output
- [ ] Verify `swift build` clean

---

## I. AppDelegate wiring

- [ ] Add `logLines`, `requestHistory`, `ramSamples`, `settings` properties
- [ ] Extend `handleLogEvent` to: append to log buffer → feed `LogWindowController`; drain `completedRequest` → history
- [ ] Start/stop `RAMPoller` with server; feed `RAMGraphWindowController`
- [ ] Add `onShowLog`, `onShowHistory`, `onShowRAMGraph`, `onShowSettings` closures wired into `StatusBarController`
- [ ] Load `AppSettings` from `~/.config/mlx-manager/settings.json` on launch; pass to `StatusBarController`
- [ ] Use `UserPresetStore.load()` instead of `Bundle.module` directly
- [ ] Verify `swift build` and manual smoke test

---

## Done

- [ ] All tests green — run `swift test`
- [ ] `swift build` produces a runnable app
