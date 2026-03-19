# Design: 008-ui-windows

## Architecture Overview

This change adds five capabilities in layers:

```
MLXManager (testable logic)          MLXManagerApp (AppKit UI)
─────────────────────────────        ──────────────────────────────────────
RequestRecord          (new)         LogWindowController        (new)
AppSettings            (new)         HistoryWindowController    (new)
UserPresetStore        (new)         RAMGraphWindowController   (new)
RAMPoller              (new)         SettingsWindowController   (new)
ServerState            (extended)    EnvironmentInstaller       (new)
StatusBarController    (extended)    AppDelegate                (extended)
```

---

## 1. Live Request Progress

### Status bar icon

The current `progressBar(fraction:)` produces `▓▓▓░░░░░░░`. We extend the title string
to append a percentage: `▓▓▓░░░░░░░ 32%`. No visual change when idle or offline.

When `AppSettings.progressStyle == .pie`, the icon uses Unicode pie glyphs instead:
`○ ◔ ◑ ◕ ●` mapped by quintile (0–20%, 20–40%, 40–60%, 60–80%, 80–100%).

### Status menu item

`StatusBarController` gains a `statusText: String` computed from state, rendered as a
disabled (non-clickable) `NSMenuItem` at the top of the menu:

| State | Text |
|-------|------|
| Offline | `Server: Offline` |
| Idle | `Server: Idle` |
| Processing | `27,611 / 41,061  (67%)` |

---

## 2. AppSettings

```swift
// MLXManager layer — no AppKit dependency
public enum ProgressStyle: String, Codable {
    case bar   // ▓▓▓░░░░░░░ 32%
    case pie   // ◑
}

public struct AppSettings: Codable, Equatable {
    public var progressStyle: ProgressStyle = .bar
    public var ramGraphEnabled: Bool = false
    public var ramPollInterval: Int = 5  // seconds: 2, 5, or 10
}
```

Persisted to `~/.config/mlx-manager/settings.json` by `AppDelegate` (simple
`JSONEncoder`/`JSONDecoder`, no dedicated class needed — settings is small).

---

## 3. UserPresetStore

Reads/writes `~/.config/mlx-manager/presets.yaml` using the existing `ConfigLoader` and
`Yams` encoder. Falls back to bundled `presets.yaml` when user file is absent.

```swift
public enum UserPresetStore {
    public static func load() -> [ServerConfig]      // user file → bundled fallback
    public static func save(_ presets: [ServerConfig]) throws
    static var userFileURL: URL                       // ~/.config/mlx-manager/presets.yaml
}
```

`ServerConfig` gains `Codable` conformance (needed for YAML round-trip).
The YAML encoding mirrors the existing `presets.yaml` schema.

---

## 4. RequestRecord & ServerState extension

```swift
public struct RequestRecord: Equatable {
    public let startedAt: Date
    public let completedAt: Date
    public let tokens: Int       // from the completing KV Caches line
    public var duration: TimeInterval { completedAt.timeIntervalSince(startedAt) }
}
```

`ServerState` gains:
- `private var requestStartedAt: Date?` — set when first `.progress` event arrives
  while status was `.idle`
- `public private(set) var completedRequest: RequestRecord? = nil` — set (replacing
  previous value) on each completion event; `AppDelegate` drains this into its history
  array after every `handle(_:)` call

No clock injection needed in tests — `Date()` is used directly; tests verify the
field is non-nil after completion, not the exact timestamp.

---

## 5. RAMPoller

Pure Swift, no Python, no psutil. Uses `proc_pidinfo` via a thin C shim or the
`libproc` approach already available on macOS:

```swift
// MLXManager layer
public final class RAMPoller {
    public var onSample: ((RAMSample) -> Void)?
    public init(pid: Int32, interval: TimeInterval)
    public func start()
    public func stop()
}

public struct RAMSample: Equatable {
    public let timestamp: Date
    public let gb: Double
}
```

Implementation: `DispatchSourceTimer` fires every `interval` seconds, calls
`proc_pidinfo(pid, PROC_PIDTASKINFO, ...)` to read `pti_resident_size`, converts
bytes → GB.

Testable via a mock: `RAMPoller` accepts a `PIDInfoProvider` protocol; real impl calls
`proc_pidinfo`; test impl returns fixed values.

---

## 6. Windows (App layer — no unit tests, visual components)

### LogWindowController

- `NSWindow` (600×400, resizable, closeable, does not release on close)
- `NSScrollView` + `NSTextView` (editable=false, font=monospaced 11pt)
- Bottom toolbar: "Clear" `NSButton`
- `func append(line: String, kind: LogLineKind)` — appends attributed string with tint
  colour per kind; auto-scrolls if `scrollView.verticalScroller.floatValue >= 0.99`
- `func clear()` — clears text storage
- Buffer: the text view itself holds the content; `AppDelegate` calls `clear()` on
  server restart

`LogLineKind`:
```swift
enum LogLineKind { case progress, kvCaches, httpCompletion, warning, other }
```

Colours: `NSColor.labelColor` (progress/other), `.systemBlue` (kvCaches),
`.systemGreen` (httpCompletion), `.systemOrange` (warning).

### HistoryWindowController

- `NSWindow` (700×300, resizable)
- Custom `HistoryChartView: NSView` — draws bars using `NSBezierPath`
- Each `RequestRecord` → one bar; bar width = `max(4, availableWidth / count)` px;
  bar height proportional to `tokens` (max tokens in history = full height)
- Bar fill colour: `NSColor.systemBlue.withAlphaComponent(durationAlpha)` where
  `durationAlpha = 0.3 + 0.7 * (duration / maxDuration)`
- `NSTrackingArea` for hover: draws tooltip via `NSToolTip` or manual overlay label
- `func update(records: [RequestRecord])` — replaces data and calls `needsDisplay = true`

### RAMGraphWindowController

- `NSWindow` (700×250, resizable)
- Custom `RAMGraphView: NSView` — line chart of `[RAMSample]`
- Y-axis auto-scaled to max observed GB (+ 10% headroom); dashed line at total physical
  RAM (`ProcessInfo.processInfo.physicalMemory` bytes → GB)
- X-axis: last N minutes (5/15/30, from `AppSettings.ramPollInterval` context — fixed
  at 30-minute window for now)
- `func update(samples: [RAMSample])` — replaces and redraws

### SettingsWindowController

- `NSWindow` (480×420, fixed size, titled "MLX Manager Settings")
- `NSTabView` with two tabs: **Presets** and **General**

**Presets tab:**
- `NSTableView` (columns: Name, Python Path, Model, Context, Extra Args)
- Each cell is an `NSTextField` (editable inline); changes update a local `[ServerConfig]`
  draft
- Below table: `+` / `−` buttons (add/remove row); "Browse…" button opens
  `NSOpenPanel` to pick python binary
- **"Set Up Environment"** section (below table, separated by `NSBox`):
  - Label: `Default python: ~/.mlx-manager/venv/bin/python`
  - Button: "Install / Reinstall mlx-lm"
  - `NSScrollView` + `NSTextView` (small, read-only) shows streaming pip output
  - On completion: alert asking "Update all presets to use this python?"

**General tab:**
- Progress style: `NSPopUpButton` (Block bar | Pie)
- RAM graph: `NSButton` checkbox "Enable RAM graph"
- RAM poll interval: `NSPopUpButton` (2s | 5s | 10s), enabled only when RAM graph is on
- "Save" `NSButton` at bottom-right — persists settings and presets, rebuilds menu,
  closes window

### EnvironmentInstaller

```swift
// App layer
final class EnvironmentInstaller {
    var onOutput: ((String) -> Void)?
    var onComplete: ((Bool) -> Void)?    // Bool = success

    func install()   // async, streams output via onOutput
    func cancel()
}
```

Steps:
1. `python3 -m venv ~/.mlx-manager/venv`
2. `~/.mlx-manager/venv/bin/pip install mlx-lm`

Uses `Process` with `Pipe`, reads `standardOutput` async, calls `onOutput` on main queue.

---

## 7. AppDelegate wiring

```swift
// New properties
private var logLines: [(String, LogLineKind)] = []     // cap 10,000
private var requestHistory: [RequestRecord] = []        // cap 500
private var ramSamples: [RAMSample] = []               // cap 1,800 (30 min @ 1s)
private var ramPoller: RAMPoller?
private var settings = AppSettings()

private var logWindowController: LogWindowController?
private var historyWindowController: HistoryWindowController?
private var ramGraphWindowController: RAMGraphWindowController?
private var settingsWindowController: SettingsWindowController?
```

`handleLogEvent` extended:
```swift
private func handleLogEvent(_ event: LogEvent) {
    let kind = LogLineKind(event)
    logLines.append((rawLine, kind))          // capped
    if logLines.count > 10_000 { logLines.removeFirst() }
    logWindowController?.append(line: rawLine, kind: kind)

    serverState.handle(event)
    statusBarController.update(state: serverState, settings: settings)

    if let record = serverState.completedRequest {
        requestHistory.append(record)
        if requestHistory.count > 500 { requestHistory.removeFirst() }
        historyWindowController?.update(records: requestHistory)
        serverState.clearCompletedRequest()
    }
}
```

`startServer` starts `RAMPoller` when `settings.ramGraphEnabled`; `stopServer` /
`handleProcessExit` stops it and calls `logWindowController?.clear()`,
resets `requestHistory` and `ramSamples`.

Menu items added to `StatusBarController`:
```
[status text — disabled]
────────────────
Start with:           ← disabled header; "Switch to:" when running
4-bit 40k             ← disabled + "(env missing)" suffix if pythonPath absent
4-bit 80k
8-bit 40k
8-bit 80k
────────────────
Stop                  ← only shown when running (absent when offline)
────────────────
Show Log
Request History
RAM Graph             ← only shown when settings.ramGraphEnabled
────────────────
Settings…
────────────────
Quit
```

### Preset availability check

`StatusBarController` accepts a `fileExists: (String) -> Bool` dependency
(default: `FileManager.default.fileExists(atPath:)`). When building the menu,
each preset's `pythonPath` is checked:

- exists → normal title, enabled when not running
- missing → title appended with `"  (env missing)"`, always disabled, no action

This prevents launching with a broken environment and nudges the user toward
Settings → "Install / Reinstall mlx-lm".

### AppKit disabled-item fix (`StatusBarView`)

`NSMenuItem` ignores `isEnabled = false` when it has an `action` selector set
(the responder chain re-enables it). Fix: only assign `action` and `target` when
`item.isEnabled == true && item.action != nil`. Items with no action or
`isEnabled: false` get `action: nil, target: nil`.

---

## 8. Bundled presets.yaml update

Change `pythonPath` in the bundled `presets.yaml` from the hardcoded local venv path to
`~/.mlx-manager/venv/bin/python` (the canonical install location). `UserPresetStore.load`
calls `NSString.expandingTildeInPath` when constructing the path at runtime.

---

## Files to create

| File | Layer |
|------|-------|
| `Sources/MLXManager/AppSettings.swift` | MLXManager |
| `Sources/MLXManager/RequestRecord.swift` | MLXManager |
| `Sources/MLXManager/UserPresetStore.swift` | MLXManager |
| `Sources/MLXManager/RAMPoller.swift` | MLXManager |
| `Sources/MLXManagerApp/LogWindowController.swift` | App |
| `Sources/MLXManagerApp/HistoryWindowController.swift` | App |
| `Sources/MLXManagerApp/RAMGraphWindowController.swift` | App |
| `Sources/MLXManagerApp/SettingsWindowController.swift` | App |
| `Sources/MLXManagerApp/EnvironmentInstaller.swift` | App |

## Files to modify

| File | Change |
|------|--------|
| `Sources/MLXManager/ServerState.swift` | Add `requestStartedAt`, `completedRequest`, `clearCompletedRequest()` |
| `Sources/MLXManager/ServerConfig.swift` | Add `Codable` conformance |
| `Sources/MLXManager/StatusBarController.swift` | Status text item; progress style param; new menu items |
| `Sources/MLXManagerApp/AppDelegate.swift` | Wire all new components |
| `Sources/MLXManagerApp/presets.yaml` | Update pythonPath to `~/.mlx-manager/venv/bin/python` |
