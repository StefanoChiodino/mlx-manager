# Design: LogTailer

## Overview

`LogTailer` watches a log file for new content, reads appended lines, parses them via `LogParser`, and delivers `LogEvent` values through a callback.

## Public API

```swift
/// Abstraction over file reading for testability.
public protocol FileHandleReading {
    func seekToEnd() -> UInt64
    func seek(toFileOffset: UInt64)
    func readDataToEndOfFile() -> Data
    var offsetInFile: UInt64 { get }
}

/// Abstraction over file system watching for testability.
public protocol FileWatcher {
    func startWatching(path: String, handler: @escaping () -> Void) -> Bool
    func stopWatching()
}

/// Tails a log file and emits parsed LogEvents via a callback.
public final class LogTailer {
    public typealias EventHandler = (LogEvent) -> Void

    public init(
        path: String,
        fileHandleFactory: @escaping (String) -> FileHandleReading?,
        watcher: FileWatcher,
        onEvent: @escaping EventHandler
    )

    /// Start tailing from the current end of file.
    public func start()

    /// Stop tailing and release resources.
    public func stop()
}
```

## Behaviour

1. **start()** — Opens the file via factory, seeks to end, begins watching for changes.
2. When the watcher fires, reads new data from the last known offset.
3. Splits data into lines, parses each via `LogParser.parse(line:)`.
4. For each non-nil `LogEvent`, calls `onEvent`.
5. Tracks the file offset; if the file shrinks (truncation), resets to offset 0.
6. **stop()** — Stops the watcher, nils out the file handle.
7. If the file doesn't exist at `start()`, watching is not started (caller can retry).

## Test Strategy

All tests use mock `FileHandleReading` and `FileWatcher` implementations — no real files.

| # | Test | Behaviour |
|---|------|-----------|
| 1 | start seeks to end | `start()` calls `seekToEnd()` on the file handle |
| 2 | new lines emitted as events | Appended progress line → `onEvent` receives `.progress` |
| 3 | non-matching lines ignored | Appended garbage → `onEvent` never called |
| 4 | multiple lines in one read | Two lines appended at once → two events emitted in order |
| 5 | partial line buffered | Data without trailing newline is held until next read |
| 6 | file truncation resets offset | File shrinks → offset resets to 0, reads from start |
| 7 | stop stops watching | After `stop()`, watcher's `stopWatching()` is called |
| 8 | file not found at start | Factory returns nil → `start()` is a no-op (no crash) |
