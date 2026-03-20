# Spec: Process Scanner — PID-File-Free Server Detection

**Change ID:** 019-process-scanner
**Status:** Archived

## Overview

Replaced `PIDFile` + `PIDRecovery` with a `ProcessScanner` that detects any
running `mlx_lm.server` process by inspecting process argv via
`sysctl(KERN_PROCARGS2)` — regardless of how the server was started.

## Components

- `ProcessScanner` — scans all PIDs, matches on `mlx_lm.server` in argv, extracts `--port`
- `SystemPIDLister` — enumerates all PIDs via `proc_listallpids()`
- `SystemProcessArgvReader` — reads argv via `sysctl(KERN_PROCARGS2)`
- `DiscoveredProcess` — value type: `pid: Int32`, `port: Int`
- `ServerManager.adoptProcess(pid:port:)` — gained optional `port` param; `pidFile` dependency removed
- `AppDelegate.recoverRunningServer()` — now calls `ProcessScanner` instead of `PIDRecovery`

## Deleted

- `PIDFile.swift`, `PIDRecovery.swift`
- `PIDFileTests.swift`, `PIDRecoveryTests.swift`

## Test Coverage

80 tests passing. New tests in:
- `ProcessScannerTests.swift` — 14 unit tests (pure logic, stub-injected)
- `SystemProcessArgvReaderTests.swift` — 2 integration tests
- `SystemPIDListerTests.swift` — 1 integration test
