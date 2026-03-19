# Proposal: LogTailer

## Problem

We have `LogParser` (pure line→event) and `ServerState` (event→state transitions), but no component that reads the server log file in real-time and bridges parsing to state updates.

## Solution

Implement `LogTailer` — a component that:

1. Tails `~/repos/mlx/Logs/server.log` (or a configurable path) from the current end-of-file
2. Reads new lines as they are appended
3. Parses each line via `LogParser`
4. Emits parsed `LogEvent` values to a caller-provided callback

## Design Constraints

- Must be testable without real files (protocol-based file handle abstraction)
- Must handle the file not existing yet (server not started)
- Must handle file truncation (log rotation)
- Callback-based design (not async/await) to keep it simple and compatible with the existing sync state machine
- No polling — use `DispatchSource.makeFileSystemObjectSource` for efficient file watching

## Scope

- `Sources/MLXManager/LogTailer.swift`
- `Tests/MLXManagerTests/LogTailerTests.swift`
- No changes to existing files
