# Log Filtering & Status Bar Formatting — Design Spec

**Date:** 2026-03-25

## Problem

1. The status bar log label shows raw log lines (after timestamp stripping), including verbose progress lines like `Prompt processing progress: 4096/9829`. These should be compact since the arc already visualises progress.
2. The KV cache regex no longer matches the new log format (`KV Caches: ... 0.00 GB, latest user cache 0 tokens`), so KV cache events are silently dropped.
3. The "show logs" popover is correct — it already displays full, untruncated raw lines. No changes needed there.

## Changes

### 1. Fix `LogParser.kvCachesRE`

The old regex `KV Caches:\s*\d+\s+seq,\s*([\d.]+)\s+GB,.*?(\d+)\s+tokens` required `\d+ seq,` which no longer appears in new-format logs (`...` instead).

New regex (backward-compatible with both formats):

```regex
KV Caches:.*?([\d.]+)\s+GB,.*?(\d+)\s+tokens
```

### 2. Update `LogLineStripper.strip(_:event:)`

Add an `event: LogEvent?` parameter. Format based on event kind before falling back to generic stripping:

| Event | Output | Notes |
| ----- | ------ | ----- |
| `.progress(current, total, _)` | `"\(current)/\(total)"` | `percentage` dropped — arc already shows it visually |
| `.kvCaches(gpuGB, tokens)` | `"\(String(format: "%.2f", gpuGB)) GB · \(tokens) tok"` | `gpuGB` formatted to 2 decimal places |
| `.httpCompletion` | raw line, stripped + truncated at 70 `String.count` chars | no special label needed |
| `nil` | raw line, stripped + truncated at 70 `String.count` chars | existing behaviour |

Signature change (the existing single-argument overload is removed; the one known call site in `AppDelegate` is updated):

```swift
public static func strip(_ line: String, event: LogEvent?) -> String
```

### 3. Update `AppDelegate`

Pass the event through to `LogLineStripper`:

```swift
statusBarController.updateLogLine(LogLineStripper.strip(line, event: event))
```

`AppDelegate.onLogEvent` already receives `event: LogEvent?`, so no additional wiring needed.

### 4. Tests

Truncation semantics (Swift grapheme cluster count, `String.count`): a string longer than 70 characters is cut at index 70 and `…` is appended, producing a 71-character result. This matches the existing `LogLineStripper` implementation. For the `httpCompletion` and `nil` paths, stripping is applied first (removes timestamp prefix if present), then truncation.

`.warning` and `.other` log kinds are produced when `event` is `nil`. They follow the same `nil` path — strip timestamp prefix and truncate — no special handling.

Any existing `LogLineStripperTests` calls using the old single-argument `strip(_:)` must be updated to `strip(_:event: nil)`.

- `LogParserTests` — add cases for:
  - New KV cache format: `"KV Caches: ... 1.54 GB, latest user cache 9826 tokens"` → `.kvCaches(gpuGB: 1.54, tokens: 9826)`
  - Old KV cache format: `"KV Caches: 2 seq, 1.54 GB, 4096 tokens"` → `.kvCaches(gpuGB: 1.54, tokens: 4096)` (regression)
- `LogLineStripperTests` — add cases for:
  - `.progress(current: 4096, total: 9829, percentage: 41.7)` → `"4096/9829"`
  - `.kvCaches(gpuGB: 1.54, tokens: 9826)` → `"1.54 GB · 9826 tok"`
  - `.kvCaches(gpuGB: 0.0, tokens: 0)` → `"0.00 GB · 0 tok"` (verify `%.2f` formatting)
  - `.httpCompletion` with line `"127.0.0.1 - - [24/Mar/2026 23:29:18] \"POST /v1/chat/completions HTTP/1.1\" 200 -"` (79 chars, no strippable prefix) → `"127.0.0.1 - - [24/Mar/2026 23:29:18] \"POST /v1/chat/completions HTTP/1…"` (71 chars)
  - `nil` event with a short plain line `"Server started"` → `"Server started"` (no truncation, no stripping)
  - `nil` event with a timestamped line `"2026-03-24 23:29:18,794 - INFO - Server started"` → `"Server started"` (prefix stripped)

## Out of Scope

- "Show logs" popover: no changes. Raw lines are stored and displayed as-is, with timestamps intact.
- `LogTailer`, `HistoricalLogLoader`, `ServerState`, `StatusBarController`: no changes.
