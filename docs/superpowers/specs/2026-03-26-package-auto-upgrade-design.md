---
name: Package Auto-Upgrade
description: Periodic and on-demand checking for mlx-lm/mlx-vlm package updates with opt-in auto-upgrade and restart notification
type: project
---

# Package Auto-Upgrade

## Overview

An opt-in feature that periodically checks whether the `mlx-lm` and `mlx-vlm` Python packages have newer versions available, automatically upgrades both venvs when updates are found, and notifies the user to restart the server if it was running during the upgrade.

## Settings

A single new field in `AppSettings`, replacing a separate toggle + interval:

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `updateCheckInterval` | Int | `0` | Hours between checks. `0` = off. Allowed: 0, 6, 12, 24 |
| `lastUpdateCheck` | Date? | `nil` | Timestamp of last successful check |
| `restartNeeded` | Bool | `false` | Set after upgrade completes while server is running |

### Settings UI

Under the existing general settings section:

- **Dropdown**: "Check for package updates" with options: Off / Every 6h / Every 12h / Every 24h
- **Button**: "Check Now" — always available regardless of dropdown value. Triggers the full check + upgrade flow (same as a periodic check)
- **Status label**: shows last check time and result (e.g. "Last checked: 2h ago — up to date" or "Update installed, restart to apply")

## PackageUpdateChecker

A new struct responsible for checking and upgrading packages.

### Check Phase

Runs `uv pip list --outdated --python <venvPython>` against both venvs (`~/.mlx-manager/venv` and `~/.mlx-manager/venv-vlm`). Parses the tabular output to detect if `mlx-lm` or `mlx-vlm` have newer versions available. Returns a result indicating whether updates were found and which packages/versions.

### Upgrade Phase

If updates are found, runs:
- `uv pip install --upgrade mlx-lm --python ~/.mlx-manager/venv/bin/python`
- `uv pip install --upgrade mlx-vlm --python ~/.mlx-manager/venv-vlm/bin/python`

Both venvs are always upgraded together, regardless of which backend is currently active.

### Execution

Runs on a background GCD queue (`userInitiated`), following the same pattern as `EnvironmentBootstrapper`. Exposes callbacks:
- `onCheckComplete(updatesFound: Bool)` — called after the check phase
- `onUpgradeComplete(success: Bool)` — called after the upgrade phase

The checker is a pure "check and optionally upgrade" unit. Scheduling logic lives in the caller.

## Scheduling

Managed by `AppDelegate` (or a small dedicated scheduler object):

1. On app launch, read `updateCheckInterval`. If `0`, do nothing.
2. Read `lastUpdateCheck`. If `nil` or `now - lastUpdateCheck >= interval`, check immediately.
3. Otherwise, schedule a one-shot `Timer` for the remaining time (`interval - elapsed`).
4. After every successful check, update `lastUpdateCheck` to `now` and schedule the next timer for the full interval.
5. If the user changes the interval in Settings (including to/from 0), cancel any existing timer and re-evaluate from step 1.

Checks only happen while the app is running. No external LaunchAgent or persistent scheduler. This is appropriate for an always-on menu bar app.

## Restart-Needed Indicator

### When to set

- Upgrade completes **and** server is currently running → set `restartNeeded = true`
- Upgrade completes **and** server is not running → `restartNeeded` stays `false` (next start uses new packages naturally)

### When to clear

- Server is started or restarted → set `restartNeeded = false`

### Persistence

`restartNeeded` is persisted in `AppSettings` so it survives app relaunch.

### Notification

When `restartNeeded` becomes true, post a macOS notification via `UNUserNotificationCenter`:

> "MLX packages updated — restart server to apply"

Repeat the notification every 2 hours while `restartNeeded` is true. Stop repeating once the server is restarted (i.e. `restartNeeded` is cleared).

### Menu

Add a "Restart to apply updates" menu item, visible only when `restartNeeded` is true. Positioned at the top of the menu. Clicking it restarts the server with the current preset.

## Testing

Following Red-Green TDD per `AGENTS.md`:

### PackageUpdateChecker
- Parse `uv pip list --outdated` output with updates available
- Parse output with no updates (empty outdated list)
- Handle error/malformed output gracefully
- Upgrade runs correct `uv pip install --upgrade` commands for both venvs

### Schedule Logic
- Timer calculation: `lastUpdateCheck` is nil → check immediately
- Timer calculation: elapsed < interval → schedule for remaining time
- Timer calculation: elapsed >= interval → check immediately
- Interval changed → existing timer cancelled, re-evaluated
- Interval set to 0 → timer cancelled, no check

### Restart-Needed State
- Set to true when upgrade completes while server is running
- Not set when server is stopped during upgrade
- Cleared when server starts/restarts

### Notification Logic
- Notification fires when `restartNeeded` becomes true
- Notification repeats every 2h while `restartNeeded` is true
- Notifications stop after server restart clears `restartNeeded`

All process execution is injected via protocol (same pattern as `EnvironmentBootstrapper`) to enable deterministic testing without real `uv` calls.

## Files Changed

| File | Action |
|------|--------|
| `Sources/MLXManager/PackageUpdateChecker.swift` | Create |
| `Sources/MLXManager/AppSettings.swift` | Add `updateCheckInterval`, `lastUpdateCheck`, `restartNeeded` |
| `Sources/MLXManager/AppDelegate.swift` (or new scheduler) | Add schedule logic, notification posting |
| `Sources/MLXManager/StatusBarController.swift` | Add "Restart to apply updates" menu item |
| `Tests/MLXManagerTests/PackageUpdateCheckerTests.swift` | Create |

No changes to `ServerManager`, `EnvironmentBootstrapper`, or `ServerConfig`.
