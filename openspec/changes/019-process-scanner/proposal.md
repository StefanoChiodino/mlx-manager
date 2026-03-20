# Proposal: Process Scanner — PID-File-Free Server Detection

**Change ID:** 019-process-scanner

## Problem

The current `PIDFile` + `PIDRecovery` stack only knows about servers that MLX
Manager itself launched (or previously tracked). If the user starts `mlx_lm.server`
manually in a terminal, the app is blind to it:

- No PID file exists → app shows "offline"
- User cannot stop, monitor RAM, or tail logs for a manually-started server
- Double-launch is possible (app launches its own copy while one already runs)

## Proposed Solution

Replace PID file–based recovery with a **process scanner** that inspects all
running processes at startup (and optionally on demand) to detect any
`mlx_lm.server` process — regardless of how it was started.

### Mechanism

Use the macOS `sysctl(KERN_PROCARGS2)` API (same kernel interface used by `ps`)
to read the full argument vector of every running process. A process is
identified as an MLX server when its argv contains `mlx_lm.server` (as the
Python module name) or its executable path ends with `mlx_lm/server.py`.

From the argv we also extract:
- `--port <n>` → the port the server is listening on
- `--model <path>` → the model being served (nice-to-have, not required)

The scanner returns a `DiscoveredProcess` value with the PID and port, which
`ServerManager.adoptProcess(pid:port:)` consumes — exactly as 012 did with a
recovered PID, but now without needing a file.

### What changes

| Component | Change |
|-----------|--------|
| `ProcessScanner` (new) | Enumerate all PIDs, read argv via `sysctl`, return first matching `DiscoveredProcess` |
| `PIDRecovery` | Deleted — replaced by `ProcessScanner` |
| `PIDFile` | Deleted — no longer written or read |
| `ServerManager` | Remove `pidFile` dependency; on `launch()` no longer writes PID; on startup calls scanner instead of recovery |
| `AppDelegate` | Call `ProcessScanner` instead of `PIDRecovery` on launch |

### Why not keep PIDFile as a fallback?

Keeping both adds complexity and split code paths. `ProcessScanner` is strictly
more capable: it detects manually-started servers that PID files never could,
and it handles the app-launched case identically (the process exists in the
process table regardless of how it started).

## Behaviour

- **App launch:** scan all processes → if mlx_lm found, adopt it (show idle,
  start log tailing, enable stop button)
- **Manual start by user:** next time the user opens the app (or on a future
  "rescan" action), the server is detected automatically
- **App-launched server:** identical behaviour — process appears in the table
  immediately, no PID file needed
- **No server running:** scanner returns nil → fresh-start state, same as before

## Out of Scope

- Periodic background scanning (can be added later)
- Multiple simultaneous MLX servers (detect first match only)
- Windows/Linux support

## Risks

| Risk | Mitigation |
|------|-----------|
| `sysctl(KERN_PROCARGS2)` is undocumented | Used by `ps`, stable since macOS 10.9; wrap in a testable protocol |
| False positives (non-MLX process with `mlx_lm` in argv) | Unlikely; match is specific to Python module path |
| Permission denied for other users' processes | `sysctl` returns error for those PIDs; skip and continue |
