# Status Bar Log Line Streaming — Design Spec

**Date:** 2026-03-22

## Summary

Stream the last log line from the server directly into the macOS menu bar status item, to the right of the existing arc/M icon. Opt-in via a Settings checkbox. Works for both `mlx_lm.server` and vision server log formats.

---

## Requirements

- **Optional:** controlled by `AppSettings.showLastLogLine` (default `false`)
- **Always-on while server is running:** last line persists until server stops (not just during processing)
- **Inline display:** arc icon stays; log text appears to its right via `NSStatusItem.button?.title`
- **Stripped format:** remove known timestamp/INFO prefixes, truncate to 70 Swift Characters
- **Cleared on server stop:** text disappears when server stops or session resets

---

## Log Stripping

A pure function `LogLineStripper.strip(_ line: String) -> String`:

Apply both strip rules first, then truncate.

1. If the line starts with a datetime+INFO prefix (pattern: `^\d{4}-\d{2}-\d{2}` … `- INFO -`), remove everything up to and including ` - INFO - `. Anchored to line start; leave unchanged if not matched.
2. If the line starts with `INFO:` followed by one or more spaces, remove through the last leading space. If not matched, leave line unchanged.
3. Truncate to 70 Swift `Character` grapheme clusters (append `…` if truncated). Using `Character` count handles multi-byte chars like `█` correctly.

Easy to extend with additional patterns later. Does not need to know server type.

### Examples

| Raw line | Stripped |
|----------|----------|
| `2026-03-22 10:09:07,338 - INFO - Prompt processing progress: 4096/24378` | `Prompt processing progress: 4096/24378` |
| `INFO:     Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)` | `Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)` |
| `127.0.0.1 - - [22/Mar/2026 10:09:03] "POST /v1/chat/completions HTTP/1.1" 200 -` | `127.0.0.1 - - [22/Mar/2026 10:09:03] "POST /v1/chat/completions HTTP/1…` (truncated at 70) |
| `Prefill: 100%|█████████▉| 23214/23215 [00:21<00:00, 1081.82tok/s]` | `Prefill: 100%|█████████▉| 23214/23215 [00:21<00:00, 1081.82tok/s]` (under 70) |

---

## Settings

### AppSettings

Add field:
```swift
public var showLastLogLine: Bool = false
```

Add to `CodingKeys` and `init(from:)` with `decodeIfPresent` (default `false`).

### Settings UI

Add a checkbox row in `SettingsWindow` general settings section:
- Label: "Show last log line in menu bar"

---

## StatusBarViewProtocol + StatusBarController

`StatusBarViewProtocol` is defined in `Sources/MLXManager/StatusBarController.swift`.

Add to `StatusBarViewProtocol`:
```swift
func updateLogLine(_ line: String?)
```

Add to `StatusBarController`:
```swift
public func updateLogLine(_ line: String?) {
    view.updateLogLine(line)
}
```

`StatusBarView` implements `updateLogLine`:
```swift
func updateLogLine(_ line: String?) {
    DispatchQueue.main.async { [weak self] in
        self?.statusItem.button?.title = line.map { " \($0)" } ?? ""
    }
}
```

(Leading space separates text from the arc view.)

---

## AppDelegate Wiring

Both server types (`mlx_lm.server` and vision) route through `handleLogEvent(_ event: LogEvent)` via `LogTailer`. The raw line is reconstructed from the event using the existing `rawLine(for:)` helper already in `AppDelegate`.

In `handleLogEvent(_ event:)`, after appending to `logLines`:
```swift
if settings.showLastLogLine {
    let stripped = LogLineStripper.strip(rawLine(for: event))
    statusBarController.updateLogLine(stripped)
}
```

In `resetSession()`:
```swift
statusBarController.updateLogLine(nil)
```

`stopServer()` and `handleProcessExit()` already call `resetSession()`, so the clear propagates through them automatically.

---

## File Map

| File | Action |
|------|--------|
| `Sources/MLXManager/LogLineStripper.swift` | Create — pure stripping function |
| `Sources/MLXManager/AppSettings.swift` | Modify — add `showLastLogLine` |
| `Sources/MLXManager/StatusBarController.swift` | Modify — add `updateLogLine` to `StatusBarViewProtocol` + `StatusBarController` |
| `Sources/MLXManagerApp/StatusBarView.swift` | Modify — implement `updateLogLine` |
| `Sources/MLXManagerApp/AppDelegate.swift` | Modify — wire stripping + `updateLogLine` calls |
| `Sources/MLXManagerApp/SettingsWindow.swift` | Modify — add checkbox |
| `Tests/MLXManagerTests/LogLineStripperTests.swift` | Create — test stripping logic |
| `Tests/MLXManagerTests/AppSettingsTests.swift` | Modify — test new field decode/encode |
| `Tests/MLXManagerTests/StatusBarControllerTests.swift` | Modify — add `updateLogLine` forwarding test |

---

## Testing

- `LogLineStripper` is a pure function — full unit test coverage for all prefix patterns, truncation, and multi-byte characters
- `AppSettings` encode/decode round-trip for `showLastLogLine`
- `StatusBarController` forwards `updateLogLine` to mock view
- No tests for `StatusBarView` or `AppDelegate` wiring (AppKit, untestable without UI)
