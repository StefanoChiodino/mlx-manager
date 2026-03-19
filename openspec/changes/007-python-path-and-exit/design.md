# Design: Python Path and Process Exit

## ServerConfig — pythonPath field

```swift
public struct ServerConfig: Equatable {
    public let name: String
    public let model: String
    public let maxTokens: Int
    public let extraArgs: [String]
    public let pythonPath: String   // ← new; full path to python binary
}
```

YAML field name: `pythonPath`. Required — missing field throws `ConfigError.missingField("pythonPath")`.

## ConfigLoader — DTO update

```swift
private struct PresetDTO: Decodable {
    let name: String?
    let model: String?
    let maxTokens: Int?
    let extraArgs: [String]?
    let pythonPath: String?         // ← new
}
```

Validation: `guard let pythonPath = dto.pythonPath else { throw ConfigError.missingField("pythonPath") }`

## ProcessLauncher — onExit parameter

```swift
public protocol ProcessLauncher {
    func launch(
        command: String,
        arguments: [String],
        onExit: @escaping () -> Void   // ← new
    ) throws -> ProcessHandle
}
```

## ServerManager — onExit property and pythonPath command

```swift
public final class ServerManager {
    public var onExit: (() -> Void)?   // ← new; called when process exits

    public func start(config: ServerConfig) throws {
        // command is now config.pythonPath, not hardcoded "python"
        process = try launcher.launch(
            command: config.pythonPath,
            arguments: [...],
            onExit: { [weak self] in
                self?.process = nil
                self?.onExit?()
            }
        )
    }
}
```

## RealProcessLauncher — terminationHandler

```swift
func launch(command: String, arguments: [String], onExit: @escaping () -> Void) throws -> ProcessHandle {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments
    process.terminationHandler = { _ in
        DispatchQueue.main.async { onExit() }
    }
    try process.run()
    return RealProcessHandle(process: process)
}
```

## AppDelegate — wiring and bundle fix

```swift
serverManager.onExit = { [weak self] in self?.handleProcessExit() }

private func handleProcessExit() {
    logTailer?.stop()
    logTailer = nil
    serverState.serverStopped()
    statusBarController.serverDidStop()
}

// Bundle.module (not Bundle.main) for SwiftPM executable targets
Bundle.module.url(forResource: "presets", withExtension: "yaml")
```

## Package.swift — resource co-location

`presets.yaml` moves from `Resources/` to `Sources/MLXManagerApp/`. Package.swift updated:

```swift
resources: [.copy("presets.yaml")]
```

## Files Changed

- `Sources/MLXManager/ServerConfig.swift`
- `Sources/MLXManager/ConfigLoader.swift`
- `Sources/MLXManager/ServerManager.swift`
- `Sources/MLXManagerApp/RealProcessLauncher.swift`
- `Sources/MLXManagerApp/AppDelegate.swift`
- `Sources/MLXManagerApp/presets.yaml` (moved from `Resources/`)
- `Package.swift`
- `Tests/MLXManagerTests/ConfigLoaderTests.swift`
- `Tests/MLXManagerTests/ServerManagerTests.swift`
