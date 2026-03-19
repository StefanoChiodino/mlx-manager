# Design: Server Control

## ProcessLauncher Protocol

Abstracts process creation so tests don't spawn real processes.

```swift
/// A handle to a launched process that can be terminated.
public protocol ProcessHandle {
    var isRunning: Bool { get }
    func terminate()
}

/// Abstraction over process launching for testability.
public protocol ProcessLauncher {
    func launch(command: String, arguments: [String]) throws -> ProcessHandle
}
```

`Foundation.Process` conforms to `ProcessHandle` via an extension (it already has `isRunning` and `terminate()`).

## ServerManager

```swift
public final class ServerManager {
    public private(set) var isRunning: Bool

    public init(launcher: ProcessLauncher)

    /// Start the server with the given config. Throws if already running.
    public func start(config: ServerConfig) throws

    /// Stop the running server. No-op if not running.
    public func stop()

    /// Restart: stop then start with the given config.
    public func restart(config: ServerConfig) throws
}
```

## CLI Argument Assembly

Given a `ServerConfig`, the full command is:

```
python -m mlx_lm.server \
  --model <config.model> \
  --max-tokens <config.maxTokens> \
  <config.extraArgs...>
```

The `ServerManager` assembles this argument list from the config and passes it to the launcher.

## Error Handling

```swift
public enum ServerError: Error, Equatable {
    case alreadyRunning
}
```

## File Location

- Source: `Sources/MLXManager/ServerManager.swift`
- Tests: `Tests/MLXManagerTests/ServerManagerTests.swift`
