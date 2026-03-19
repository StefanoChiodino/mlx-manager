# Proposal: PID File Recovery

**Change ID:** 012-pid-recovery
**Status:** proposed

## Problem

When the user quits MLX Manager while the server is running and relaunches the app,
`ServerManager` initialises with `process = nil` and reports `isRunning = false`.
The UI shows the server as offline even though the mlx_lm.server process is still
alive. Clicking "Start" launches a **second** server, risking GPU OOM.

## Root Cause

`ServerManager` only knows about processes it launched in the current session.
There is no persistence of the server PID across app restarts and no attempt to
discover an existing server process on launch.

## Proposed Solution

1. **Write a PID file** (`~/.config/mlx-manager/server.pid`) when the server starts.
2. **Delete the PID file** when the server stops (explicit stop, restart, or process exit).
3. **On app launch**, read the PID file, check if that process is still alive
   (`kill(pid, 0)`), and if so, **adopt** it — set state to running and resume
   log tailing.
4. If the PID file exists but the process is dead, delete the stale PID file and
   treat the server as offline.

## Scope

- New: `PIDFile` value type — read/write/delete PID file, check process liveness.
- Modified: `ServerManager` — write PID on start, delete on stop, expose `adoptProcess(pid:)`.
- Modified: `AppDelegate` — call PID recovery on launch before building UI state.

## Out of Scope

- Port-based detection (checking if localhost:8080 is listening).
- Sending signals to adopted processes (terminate still works via `kill(pid, SIGTERM)`).
- Multiple simultaneous servers.
