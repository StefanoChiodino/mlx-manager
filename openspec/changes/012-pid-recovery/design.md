# Design: PID File Recovery

**Change ID:** 012-pid-recovery

## Overview

Persist the server process PID to disk so the app can recover its running state
after a quit-and-relaunch cycle. This prevents accidental double-launch of the
MLX server.

## Components

### 1. PIDFile (new — `Sources/MLXManager/PIDFile.swift`)

A value type that encapsulates PID file I/O and process liveness checks.

```swift
public struct PIDFile {
    let url: URL

    /// Write a PID to the file. Creates parent directories if needed.
    func write(pid: Int32) throws

    /// Read the PID from the file, or nil if the file doesn't exist or is malformed.
    func read() -> Int32?

    /// Delete the PID file. No-op if it doesn't exist.
    func delete()

    /// Check if a process with the given PID is still alive (kill(pid, 0)).
    static func isProcessAlive(pid: Int32) -> Bool
}
```

**File location:** `~/.config/mlx-manager/server.pid`

The file contains only the PID as a decimal string (e.g. `"12345"`).

**Protocols for testability:**

```swift
public protocol PIDFileReading {
    func read() -> Int32?
    func delete()
    static func isProcessAlive(pid: Int32) -> Bool
}

public protocol PIDFileWriting {
    func write(pid: Int32) throws
    func delete()
}
```

`PIDFile` conforms to both. Tests inject mocks.

### 2. ServerManager changes

- Accept an optional `PIDFileWriting` dependency in `init`.
- After a successful `launch()`, call `pidFile.write(pid:)`.
- In `stop()` and the `onExit` cleanup path, call `pidFile.delete()`.

### 3. PIDRecovery (new — `Sources/MLXManager/PIDRecovery.swift`)

A pure function (or small struct) that reads the PID file and determines
what to do:

```swift
public enum RecoveryResult: Equatable {
    case noFile              // No PID file found — fresh start
    case staleFile           // PID file exists but process is dead — cleaned up
    case adopted(pid: Int32) // Process is alive — adopt it
}

public struct PIDRecovery {
    func recover(pidFile: PIDFileReading) -> RecoveryResult
}
```

### 4. AppDelegate changes

In `applicationDidFinishLaunching`, after creating `ServerManager` but before
building the `StatusBarController`:

1. Call `PIDRecovery().recover(pidFile:)`.
2. If `.adopted(pid)`: set `serverManager` state to running (new method),
   update UI to idle, start log tailing.
3. If `.staleFile`: PID file already cleaned up, proceed normally.
4. If `.noFile`: proceed normally.

### 5. ServerManager.adoptProcess(pid:)

A new method that sets the manager into a "running but not owning the Process
handle" state. Since we don't have a `ProcessHandle` for an adopted process,
we need a lightweight alternative:

- Store the adopted PID directly (`private var adoptedPID: Int32?`).
- `isRunning` returns `true` if `adoptedPID != nil` and the process is alive.
- `stop()` sends `SIGTERM` via `kill(adoptedPID, SIGTERM)` and clears state.
- `pid` returns `adoptedPID` when in adopted mode.

## Data Flow

```
App Launch
    │
    ▼
PIDRecovery.recover()
    │
    ├── .noFile ──────────► normal startup (offline)
    ├── .staleFile ───────► delete file, normal startup (offline)
    └── .adopted(pid) ────► ServerManager.adoptProcess(pid)
                                │
                                ▼
                           UI shows idle, log tailing starts
```

## Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| PID file contains garbage | `read()` returns nil → treated as `.noFile` |
| PID file exists, process dead | `.staleFile` — file deleted, start offline |
| PID file exists, process alive but not mlx_lm | Accepted — we trust the PID file |
| App crashes without cleanup | Next launch reads PID, checks liveness, recovers |
| Two app instances race | Out of scope (macOS menu bar apps are single-instance) |
