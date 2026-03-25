# Prefill Tok/s in Status Bar

**Date:** 2026-03-25
**Status:** Approved

## Overview

Display the prefill (prompt processing) speed in tokens per second in the menu bar status text. The value shown is from the most recent request for which a reliable measurement was possible. The feature is opt-in via a General settings checkbox.

## Metric Definition

**Prefill tok/s** = `tokens / elapsed` where:

- `tokens` = token count (`current`) from the final progress line of the qualifying batch
- `elapsed` = time between the **log-line timestamps** of the first and last progress line of that batch (never wall clock — this must work correctly during historical log replay)

A **qualifying batch** is a sequence of ≥2 consecutive `Prompt processing progress:` log lines with **no interrupting events** (no KV Caches, no HTTP completion, no other event type) between them, and `elapsed >= 0.1` seconds (to guard against same-second lines producing absurdly large values).

If a batch is interrupted after only one progress line, it does not qualify and the displayed value does not change.

## LogEvent Change

`LogEvent.progress` gains a `timestamp: Date` field (non-optional), parsed from the log line prefix:

```
2026-03-25 10:41:25,583 - INFO - Prompt processing progress: 4096/33242
```

**Timestamp parsing:** Use `DateFormatter` with `locale = Locale(identifier: "en_US_POSIX")` and `timeZone = TimeZone.current` (log timestamps are local time). Format string: `"yyyy-MM-dd HH:mm:ss,SSS"`. If parsing fails, `LogParser.parse(_:)` returns `nil` for the entire line — the event is discarded, same as any unrecognised line.

**Migration note:** This is a breaking change to the enum. All existing switch arms on `.progress` must be updated as part of the same refactor step, in all files that pattern-match or construct `.progress`:

- `LogParser.swift` — the parse site
- `LogLineKind.swift` (or the `LogLineKind.init` in `LogParser.swift`) — trivial: just add `_` for the new label, no value binding needed
- `ServerState.swift` — destructures `(current, total, _)`, add `timestamp` binding
- `ServerCoordinator.swift` — `rawLine(for:)` pattern-matches `.progress(current, total, _)`, add `_` for timestamp
- All tests in `LogParserTests`, `ServerStateTests`, and any other file constructing `.progress`

All existing tests must remain green throughout this refactor before any new red tests are written.

## Data Flow

```
LogParser
  └─ .progress(current, total, percentage, timestamp)

ServerState (accumulator fields, all private)
  ├─ firstProgressAt: Date?      ← set on first progress of a batch
  ├─ lastProgressAt: Date?       ← updated on every consecutive progress
  ├─ lastProgressTokens: Int     ← current token count from last progress line
  ├─ progressCount: Int          ← consecutive progress event count
  └─ pendingPrefillTPS: Double?  ← computed when a qualifying batch completes;
                                    persists until replaced or cleared on stop/crash

On .progress event (always accumulate, regardless of current status):
  → if progressCount == 0: set firstProgressAt = event.timestamp
  → set lastProgressAt = event.timestamp
  → set lastProgressTokens = event.current
  → increment progressCount

On any non-progress log event (only when status != .offline, consistent with existing guard):
  → if progressCount >= 2:
      let elapsed = lastProgressAt!.timeIntervalSince(firstProgressAt!)
      if elapsed >= 0.1:
          pendingPrefillTPS = Double(lastProgressTokens) / elapsed
      (else: leave pendingPrefillTPS unchanged — too short to be meaningful)
  → reset accumulator: firstProgressAt = nil, lastProgressAt = nil,
                        lastProgressTokens = 0, progressCount = 0
  → proceed with normal event handling

RequestRecord
  └─ prefillTPS: Double?   ← copied from pendingPrefillTPS when record is emitted;
                              nil if no qualifying batch has completed yet
```

**Accumulator reset (all five fields including `pendingPrefillTPS`) also occurs on:** `serverStopped()` and `serverCrashed()`.

**Value-type invariant:** `ServerState` is a struct. In `ServerCoordinator.handleLogEvent`, `onStateChange?(state)` is called before `state.clearCompletedRequest()`. This means `StatusBarController.update(state:)` receives a value-type snapshot that still contains `completedRequest`. This call order must be preserved — do not swap the two calls.

## StatusBarController

`StatusBarController` gains:

```swift
private(set) var lastPrefillTPS: Double?
```

`private(set)` (not fully `private`) so tests using `@testable import` can observe it directly.

**Updating `lastPrefillTPS`:** Done inside `update(state:)`:

- If `state.completedRequest?.prefillTPS` is non-nil → update `lastPrefillTPS`
- If `state.completedRequest?.prefillTPS` is nil → leave `lastPrefillTPS` unchanged

**Clearing `lastPrefillTPS`:** Set to `nil` when `update(state:)` is called with `state.status == .offline` or `.failed`. This covers both the graceful stop path (`.offline`) and the crash path (`.failed`). Additionally clear in `serverDidStop()` as belt-and-suspenders for the explicit stop path.

**Toggling the setting off** does NOT clear `lastPrefillTPS` — the setting gates display only.

**Display — where it happens:** The prepend is performed inside `AppDelegate.onLogEvent` (the same site that already calls `statusBarController.updateLogLine(_:)`), not inside `StatusBarController.update(state:)`. `AppDelegate` reads `statusBarController.lastPrefillTPS` and `settings.showPrefillTPS` when building the string passed to `updateLogLine(_:)`.

Format: when `showPrefillTPS == true` and `lastPrefillTPS != nil`:

- If log line also shown: `"\(Int(tps.rounded())) tok/s  \(logLine)"`
- If only TPS shown: `"\(Int(tps.rounded())) tok/s"`
- Values below 1.0 tok/s display as `"0 tok/s"` (standard rounding; no special casing needed)

This requires no new methods on `StatusBarViewProtocol`.

## Settings

`AppSettings` gains:

```swift
var showPrefillTPS: Bool = false
```

- Add `showPrefillTPS` to the `CodingKeys` enum in `AppSettings`
- Serialise using `decodeIfPresent` with a `false` default — follow the exact same pattern as `showLastLogLine`

General tab gains a checkbox: **"Show prefill speed (tok/s)"**, positioned after the existing "Show last log line" checkbox.

## What Does Not Change

- `RequestRecord.startedAt` / `completedAt` / `tokens` / `duration` — unchanged
- Existing request history chart — unchanged
- Status bar layout for users with `showPrefillTPS = false` — unchanged

## Testing Order

1. **Refactor (green → green):** Add `timestamp: Date` to `LogEvent.progress`. Update all switch arms and test constructions listed in the migration note above. All tests must pass.
2. **RED:** `LogParser` — timestamp parsed correctly including milliseconds (`,583`); returns `nil` on unparseable timestamp.
3. **RED:** `ServerState` — qualifying batch (≥2 lines, elapsed ≥ 0.1s, status `.processing`) → `pendingPrefillTPS` computed and copied to `RequestRecord.prefillTPS`; interrupted batch → `prefillTPS` nil; single line → nil; `elapsed < 0.1s` → `pendingPrefillTPS` unchanged.
4. **RED:** `ServerState` — accumulator (all five fields) resets on `serverStopped()` / `serverCrashed()`.
5. **RED:** `StatusBarController.lastPrefillTPS` — updates on qualifying record; persists on non-qualifying; clears when `update(state:)` called with `.offline` or `.failed`; clears on `serverDidStop()`.
6. **RED:** `AppSettings` — `showPrefillTPS` round-trips through JSON; old JSON without the key deserialises as `false`.
