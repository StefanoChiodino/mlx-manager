# Tasks: 019-process-scanner

## Phase 1 — New types (TDD, no deletions yet)

- [x] **T1** `DiscoveredProcess` struct: `pid: Int32`, `port: Int`, `Equatable`
  - Test: `test_discoveredProcess_equality`

- [x] **T2** `PIDListing` protocol + `StubPIDLister` for tests
  - No production test (protocol only); stub used in T5+

- [x] **T3** `ProcessArgvReading` protocol + `StubProcessArgvReader` for tests
  - No production test; stub used in T5+

- [x] **T4** `ProcessScanner` — no processes → returns nil
  - Test: `test_findMLXServer_noProcesses_returnsNil`

- [x] **T5** `ProcessScanner` — processes present but none match → returns nil
  - Test: `test_findMLXServer_noMLXProcess_returnsNil`

- [x] **T6** `ProcessScanner` — argv contains `mlx_lm.server` as `-m` argument → returns `DiscoveredProcess`
  - Test: `test_findMLXServer_mlxModuleInArgv_returnsDiscoveredProcess`

- [x] **T7** `ProcessScanner` — argv contains `mlx_lm.server` as bare element → returns `DiscoveredProcess`
  - Test: `test_findMLXServer_mlxServerBareArgv_returnsDiscoveredProcess`

- [x] **T8** `ProcessScanner` — argv contains path ending in `mlx_lm/server.py` → returns `DiscoveredProcess`
  - Test: `test_findMLXServer_mlxScriptPathInArgv_returnsDiscoveredProcess`

- [x] **T9** `ProcessScanner` — `--port 9000` in argv → `port == 9000`
  - Test: `test_findMLXServer_customPort_extractsPort`

- [x] **T10** `ProcessScanner` — no `--port` flag → `port == 8080`
  - Test: `test_findMLXServer_noPortFlag_defaultsTo8080`

- [x] **T11** `ProcessScanner` — `--port` is last element (no value) → `port == 8080`
  - Test: `test_findMLXServer_portFlagNoValue_defaultsTo8080`

- [x] **T12** `ProcessScanner` — `--port abc` (non-numeric) → `port == 8080`
  - Test: `test_findMLXServer_portFlagNonNumeric_defaultsTo8080`

- [x] **T13** `ProcessScanner` — argv returns nil for a PID → skips that process
  - Test: `test_findMLXServer_argvUnavailable_skipsProcess`

- [x] **T14** `ProcessScanner` — multiple processes, first is MLX → returns first
  - Test: `test_findMLXServer_multipleProcesses_returnsFirst`

## Phase 2 — `SystemProcessArgvReader` (integration-style, reads real process)

- [x] **T15** `SystemProcessArgvReader` — current process PID → argv contains test executable path
  - Test: `test_argv_currentProcess_containsExecutablePath`

- [x] **T16** `SystemProcessArgvReader` — non-existent PID → returns nil
  - Test: `test_argv_nonExistentPID_returnsNil`

## Phase 3 — `SystemPIDLister` (integration-style)

- [x] **T17** `SystemPIDLister.allPIDs()` — returns non-empty list containing current PID
  - Test: `test_allPIDs_containsCurrentProcess`

## Phase 4 — Wire up & delete old code

- [x] **T18** `ServerManager` — remove `pidFile` dependency; update `adoptProcess(pid:)` to accept optional `port:` parameter; update existing `ServerManagerTests`

- [x] **T19** `AppDelegate` — replace `PIDRecovery` call with `ProcessScanner().findMLXServer()`

- [x] **T20** Delete `PIDFile.swift`, `PIDRecovery.swift`, `PIDFileTests.swift`, `PIDRecoveryTests.swift`

- [x] **T21** Update `project.md` architecture table to replace PIDFile/PIDRecovery with ProcessScanner
