# Auto-Restart on Crash — Design Spec

## Summary

Add a configurable setting that automatically restarts the MLX server when it crashes, with a rate limit to prevent restart loops. When the rate limit is exhausted, post a macOS notification and stop.

## Setting

- `autoRestartEnabled: Bool` in `AppSettings`, default `true`
- Persisted to `~/.config/mlx-manager/settings.json`
- Exposed in Settings UI as a checkbox: "Restart server automatically after crash"

## CrashRestartPolicy

New value type in `Sources/MLXManager/CrashRestartPolicy.swift`.

```swift
public struct CrashRestartPolicy {
    let maxRestarts: Int       // hardcoded: 3
    let window: TimeInterval   // hardcoded: 180 (3 minutes)
    private(set) var crashTimestamps: [Date]

    mutating func recordCrash(at: Date) -> Bool
    mutating func reset()
}
```

### Behaviour

- `recordCrash(at:)` appends the timestamp, evicts entries older than `window`, then returns `true` if `crashTimestamps.count < maxRestarts` (restart allowed) or `false` (exhausted). With `maxRestarts = 3`, this allows up to 3 restart attempts before stopping.
- `reset()` clears `crashTimestamps`. Called on manual `start()` and `stop()`.

### Testability

Pure value type — inject dates to test windowing and exhaustion without real timers.

## ServerCoordinator Changes

### New state

- `private var crashRestartPolicy = CrashRestartPolicy()`
- `private var lastConfig: ServerConfig?` — saved on `start()`, used for restart
- `public var autoRestartEnabled: Bool = true`
- `private let restartDelay: TimeInterval` — constructor parameter, default 2.0 (overridable in tests)

### New callbacks

- `onAutoRestart: (() -> Void)?` — fired when the coordinator is about to auto-restart (server died, restart imminent)
- `onRestartExhausted: (() -> Void)?` — fired when the rate limit is exhausted

### Modified `handleProcessExit()`

1. Stop log tailer, set state to `.failed`.
2. If `autoRestartEnabled` is off, or no `lastConfig` exists → fire `onProcessExit` (existing behaviour).
3. Ask `crashRestartPolicy.recordCrash()`:
   - **Allowed:** fire `onAutoRestart`, then after `restartDelay` seconds (`DispatchQueue.main.asyncAfter`), call `start(config: lastConfig)`.
   - **Exhausted:** fire `onProcessExit`, then fire `onRestartExhausted`.

### Modified `start()` and `stop()`

- `start()` saves the config to `lastConfig` and calls `crashRestartPolicy.reset()`.
- `stop()` calls `crashRestartPolicy.reset()` and sets `lastConfig = nil` (manual stop clears crash history and prevents stale restarts).

## AppDelegate Changes

### Wiring

- Set `serverCoordinator.autoRestartEnabled` from `settings.autoRestartEnabled` at init and on settings change.
- `onProcessExit` — same as today: stop RAM polling, stop gateway, reset session, update status bar.
- `onAutoRestart` — stop RAM polling only (PID changes); do NOT reset session or stop gateway.
- `onRestartExhausted` — post macOS notification.

### After successful auto-restart

The existing `start()` path handles re-establishing RAM polling. The gateway is left running during auto-restart cycles since the backend port doesn't change.

### Notification

Use `UNUserNotificationCenter`:
- Request `.alert` permission at app launch.
- On exhaustion, post:
  - **Title:** "MLX Server Stopped"
  - **Body:** "Server crashed 3 times in 3 minutes. Automatic restart disabled."

## Settings UI

Add checkbox in the general settings section of `SettingsWindowController`:
- Label: "Restart server automatically after crash"
- Bound to `autoRestartEnabled`
- Same pattern as existing `ramGraphEnabled` checkbox.

## Files Changed

| File | Change |
|------|--------|
| `Sources/MLXManager/CrashRestartPolicy.swift` | New — policy value type |
| `Tests/MLXManagerTests/CrashRestartPolicyTests.swift` | New — policy tests |
| `Sources/MLXManager/AppSettings.swift` | Add `autoRestartEnabled` field |
| `Tests/MLXManagerTests/AppSettingsTests.swift` | Test new field encoding/decoding |
| `Sources/MLXManager/ServerCoordinator.swift` | Auto-restart logic, new callbacks |
| `Tests/MLXManagerTests/ServerCoordinatorTests.swift` | Test restart and exhaustion paths |
| `Sources/MLXManagerApp/AppDelegate.swift` | Wire callbacks, notification permission, post notification |
| `Sources/MLXManagerApp/SettingsWindowController.swift` | Add checkbox |

## Edge Cases

- **Adopted process crash:** The coordinator's `handleProcessExit` already handles adopted processes. Auto-restart does NOT apply to adopted processes (we don't have the config to restart with). Only coordinator-started processes are eligible.
- **Rapid crash (< restartDelay):** The 2-second delay prevents overlapping restart attempts.
- **Settings changed during restart cycle:** If the user disables auto-restart while a restart is pending, the next crash won't trigger another restart.
- **Manual stop during restart delay:** `stop()` resets the policy and clears `lastConfig`, cancelling any pending restart.
