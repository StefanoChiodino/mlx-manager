# MLX Manager Refactor Review

Date: 2026-03-24

## Context

Goal: make `MLX Manager` feel like a reliable replacement for running `mlx` from Terminal.

Current user-reported pain points:

- intermittent instability
- too much fiddling with model/config setup
- generally works, but needs cleanup during the refactor

## How To Use This File

- Keep `Status` updated as each item is triaged, fixed, or intentionally deferred.
- Add implementation notes under `Refactor Notes`.
- Use this as the working review doc during the current architecture refactor.

## Summary

| ID | Priority | Status | Area | Summary |
|---|---|---|---|---|
| F1 | P1 | Open | Preset management | Post-install preset updates can corrupt working configs |
| F2 | P2 | Partial | Environment bootstrap | Bootstrap now checks missing backends, but still installs only one per launch |
| F3 | P1 | Fixed | Request history | Idle HTTP completions no longer create fake request records |
| F4 | P2 | Fixed | Status/UI accuracy | Default threshold changed to 0, waits for real completion signal |
| F5 | P2 | Closed | Log/history state | Pre-refactor duplicate replay path appears removed |

---

## F1 — P1 — Post-install preset updates can corrupt working configs

Status: Open

Files:

- `Sources/MLXManagerApp/SettingsWindowController.swift:684`
- `Sources/MLXManagerApp/SettingsWindowController.swift:418`
- `Sources/MLXManagerApp/SettingsWindowController.swift:599`

### What is happening

After a successful environment install, clicking `Update Presets` rebuilds every preset with the minimal `ServerConfig` initializer:

- non-default fields like `port`, `prefillStepSize`, `trustRemoteCode`, cache settings, and VLM KV settings are dropped back to defaults
- the replacement `pythonPath` always comes from `EnvironmentInstaller.pythonPath`, which is the legacy LM path

Related editor behavior makes this worse:

- new presets default to the LM python path
- switching a preset from LM to VLM keeps the old python path instead of moving to the backend-specific one

### Why it matters

This is the most likely source of the “model configs are annoying to fiddle with” problem. A user can do the right thing in the installer UI and still end up with silently broken or degraded presets, especially for VLM.

### Suggested direction

- preserve every existing preset field when updating the python path
- update only presets that match the installed backend
- use `EnvironmentInstaller.pythonPath(for:)` instead of the legacy LM-only accessor
- auto-correct backend-specific python paths when creating or changing backend type

### Refactor Notes

- 2026-03-24 post-refactor implementation: `ServerState` now emits records only for real in-flight requests, so idle HTTP completions no longer synthesize phantom history entries.

---

## F2 — P2 — Bootstrap now checks missing backends, but still installs only one per launch

Status: Partial

Files:

- `Sources/MLXManagerApp/AppDelegate.swift:100`

### What is happening

The refactor improved this path. `bootstrapEnvironmentIfNeeded(presets:)` now derives the set of backends present in the configured presets and checks which environments are missing.

What remains:

- only one missing backend is installed per launch
- the backend chosen comes from a `Set`, so the install order is not explicit
- if both LM and VLM are missing, one of them still stays unavailable until a later launch or manual install

### Why it matters

This is much better than the pre-refactor behavior, but the first-launch experience is still incomplete on a clean machine with multiple backend types configured.

### Suggested direction

- either install all missing backends in sequence
- or make the bootstrap policy explicit: active preset first, with a clear follow-up affordance for the rest

### Refactor Notes

- Post-refactor review: original finding no longer applies exactly. Severity reduced.

---

## F3 — P1 — Idle HTTP completions create fake request records

Status: Fixed

Files:

- `Sources/MLXManager/ServerState.swift:66`
- `Sources/MLXManager/HistoricalLogLoader.swift:16`

### What is happening

When an HTTP completion line arrives while `ServerState` is already idle, the code:

- synthesizes `requestStartedAt = Date()`
- emits a completed request with `tokens ?? 0`

That means stray `POST /v1/chat/completions ... 200` lines can create phantom history entries. Historical replay uses the same state machine, so old startup sequences can also become fake requests.

### Why it matters

This makes `Request History` untrustworthy. It also muddies refactor work because the history layer is currently reporting events that never represented a real active request.

### Suggested direction

- only emit a completed request when there was an actual in-flight request
- treat idle HTTP completions as state confirmation, not as a new record
- consider parsing timestamps if historical replay is expected to produce meaningful durations

### Refactor Notes

- 

---

## F4 — P2 — Default threshold reports idle before MLX is actually done

Status: Fixed

Files:

- `Sources/MLXManager/StatusBarController.swift:89`
- `Sources/MLXManager/AppSettings.swift:9`

### What is happening

The status item flips to `.idle` once progress crosses the configured threshold, and the default threshold is `99`.

But MLX completion is actually signaled later by:

- `KV Caches: ...`
- `POST /v1/chat/completions ... 200`

So the menu bar can report `Server: Idle` while the request is still running.

### Why it matters

If the app is meant to replace the Terminal workflow, the status item needs to feel trustworthy. Early idle transitions make the app feel flaky even if the server itself is behaving normally.

### Suggested direction

- default to completion-signal-driven state only
- keep threshold behavior, if retained, as an opt-in compatibility tweak rather than the default

### Refactor Notes

- 2026-03-24 post-refactor implementation: default `progressCompletionThreshold` changed from `99` to `0`, so the app now stays in `.processing` by default until the real completion signal arrives.

---

## F5 — P2 — Pre-refactor duplicate replay path appears removed

Status: Closed

Files:

- `Sources/MLXManagerApp/AppDelegate.swift:117`
- `Sources/MLXManagerApp/AppDelegate.swift:212`

### What is happening

This looked real before the refactor, but the control flow has changed:

- log tailing is now owned by `ServerCoordinator`
- Settings dismissal updates the existing `StatusBarController` instead of rebuilding and re-recovering the running process
- the specific “open Settings, close Settings, duplicate replay” path no longer appears to be present

There is still append-based historical loading in `loadHistoricalLog()`, so this area is worth keeping an eye on, but the original reproduction path seems gone.

### Refactor Notes

- Post-refactor review: marking the original finding closed unless a new reproduction path turns up.

---

## Verification Notes

- `swift test` required running outside the sandbox because SwiftPM needed writable compiler caches.
- The XCTest target passed.
- The Swift Testing suite is not fully green yet: `Tests/MLXManagerTests/ServerManagerTests.swift` still has two stale expectations around argument ordering.
