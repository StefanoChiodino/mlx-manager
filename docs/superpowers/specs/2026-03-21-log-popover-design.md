# Log Popover + Historical Log Loading

## Problem

Two bugs and a UX inconsistency:

1. **Log window opens behind other windows** and cannot be reached via Cmd-Tab (menu bar apps don't participate in the app switcher). The window is an `NSWindow` while RAM Graph and Request History use `NSPopover` — inconsistent.
2. **Log is empty on open** — `LogTailer.start()` seeks to end of file and only shows new lines. If the user opens the log after activity has occurred, they see nothing.
3. **Request History is empty** — `requestHistory` is populated from `ServerState.completedRequest` which only fires for events seen *after* tailing starts. Historical log lines are never parsed for request records.

## Design

### Part 1: Convert Log Window to Popover

Replace `LogWindowController` (NSWindow-based) with a popover shown from the status bar, matching the pattern used by `showRAMGraphView` and `showHistoryView` in `StatusBarView`.

**Changes:**

- **Move `LogLineKind` to `MLXManager` framework** — Currently in the app target (`LogWindowController.swift`). Must move to the framework (e.g., alongside `LogParser.swift`) since it will be used in `StatusBarViewProtocol` which lives in the framework target.
- **`StatusBarViewProtocol`** — Add `showLogView(lines: [(String, LogLineKind)])`. No `closeLogView()` needed — `.transient` popover dismisses itself (consistent with `closeRAMGraphView`/`closeHistoryView` which are unused no-ops).
- **`StatusBarView`** — Implement `showLogView` using `NSPopover` (500x400pt, `.transient` behavior). Content is a `LogPopoverView` (new `NSView` subclass) containing an `NSScrollView` + `NSTextView` with the same monospace/color-coded styling as the current `LogWindowController`. No "Clear" button — the popover is a snapshot of the buffer.
- **`StatusBarController`** — Add `showLogView(lines:)` that forwards to the view protocol. `onShowLog` callback stays `(() -> Void)?` — AppDelegate already has access to `logLines` and calls `showLogView` directly.
- **`AppDelegate`** — Maintain an in-memory `logLines: [(String, LogLineKind)]` buffer (capped at 10,000 entries). `showLog()` calls `statusBarController.showLogView(lines: logLines)`. Remove `logWindowController` property and its reference in `resetSession()`. `handleLogEvent` appends to `logLines` instead of calling `logWindowController?.append(...)`. `resetSession()` clears `logLines`.
- **Delete `LogWindowController.swift`** — Replaced by the popover.
- **New: `LogPopoverView.swift`** — In the app target. Renders `[(String, LogLineKind)]` into a color-coded `NSTextView`. Scrolled to bottom on display.

**The popover is a snapshot** — it shows the contents of `logLines` at the time it opens. New log lines arriving while the popover is open are not appended. This matches how the RAM graph and history popovers work (snapshot, not live). Users who want to see new lines close and reopen the popover.

### Part 2: Load Last 100 Lines From Disk

Pre-populate the log buffer from the log file on disk when tailing starts.

**Changes:**

- **`AppDelegate.loadHistoricalLog()`** — New private method:
  1. Read the log file at `logPath` from disk.
  2. Split into lines, take the last 100.
  3. Parse each through `LogParser.parse(line:)`.
  4. For lines that parse: append `(rawLine, LogLineKind(event))` to `logLines` where `rawLine` is the **original text from disk** (not the synthetic `rawLine(for:)` reconstruction used for live events).
  5. For lines that don't parse (`nil`): append as `(rawLine, .other)`.
  6. Feed parsed events through a **separate `ServerState` instance** (not the live `serverState`) to extract `RequestRecord`s. Append any completed requests to `requestHistory`.
- **Separate `ServerState` for historical parsing** — Using the live `serverState` would leave it in a potentially wrong state (e.g., `.processing` if the last historical event was a progress line). Instead, create a temporary `ServerState`, call `.serverStarted()`, feed historical events, extract records, then discard it.
- **Call `loadHistoricalLog()`** in `startTailing()` *before* starting the tailer. Both `recoverRunningServer()` and `startServer()` call `serverState.serverStarted()` before `startTailing()`, so ordering is safe.
- **Deduplication** — Since `LogTailer.start()` seeks to EOF, historical lines won't overlap with tailed lines. No dedup needed.

### Part 3: Request History From Historical Lines

Falls out naturally from Part 2. The temporary `ServerState` in `loadHistoricalLog()` emits `completedRequest` records for any complete request sequences (progress → kvCaches/httpCompletion) found in the last 100 lines. These are appended to `requestHistory`.

**Caveat:** The state machine requires seeing a `progress` event before `kvCaches`/`httpCompletion` to emit a record. If the last 100 lines contain a completion without its preceding progress, that request won't appear in history. Acceptable — partial data at the edges is expected.

## Files Changed

| File | Change |
|------|--------|
| `Sources/MLXManager/LogParser.swift` | Add `LogLineKind` enum (moved from app target) |
| `Sources/MLXManager/StatusBarController.swift` | Add `showLogView(lines:)` to protocol and controller |
| `Sources/MLXManagerApp/StatusBarView.swift` | Implement `showLogView` with NSPopover + `LogPopoverView` |
| `Sources/MLXManagerApp/LogWindowController.swift` | Delete (replaced by popover) |
| `Sources/MLXManagerApp/AppDelegate.swift` | Add `logLines` buffer, `loadHistoricalLog()`, wire up popover, remove `logWindowController` |
| New: `Sources/MLXManagerApp/LogPopoverView.swift` | NSView with NSScrollView+NSTextView for log display |

## Testing

- **`LogParser` tests** — Already exist, no changes needed.
- **`StatusBarController` tests** — Add test that `showLogView` is called with correct lines when `onShowLog` fires.
- **Historical log loading** — Unit test for `loadHistoricalLog()`: verify last 100 lines are read, parsed events populate `requestHistory`, unparseable lines preserved as `.other`. Use a temporary file with known content.
- **Manual testing** — Start server, make requests, click "Show Log" — should see last 100 lines. Click "Request History" — should see bars for historical requests.

## Out of Scope

- Live updating popover (new lines appear while open)
- Log search/filtering
- Log export
- Clear button in popover
- Persistent log line buffer across app restarts (beyond reading from disk)
