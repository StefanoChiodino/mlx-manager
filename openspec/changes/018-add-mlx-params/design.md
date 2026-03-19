# Design: Add MLX Server Parameters

## Changes

### ServerConfig (Sources/MLXManager/ServerConfig.swift)

Add fields to struct:

```swift
public struct ServerConfig: Equatable, Codable {
    public let name: String
    public let model: String
    public let maxTokens: Int
    public let port: Int
    public let prefillStepSize: Int
    public let promptCacheSize: Int
    public let promptCacheBytes: Int
    public let trustRemoteCode: Bool
    public let enableThinking: Bool
    public let extraArgs: [String]
    public let pythonPath: String
    
    public init(
        name: String,
        model: String,
        maxTokens: Int,
        port: Int = 8080,
        prefillStepSize: Int = 4096,
        promptCacheSize: Int = 4,
        promptCacheBytes: Int = 10 * 1024 * 1024 * 1024,
        trustRemoteCode: Bool = false,
        enableThinking: Bool = false,
        extraArgs: [String] = [],
        pythonPath: String
    )
}
```

### ServerManager (Sources/MLXManager/ServerManager.swift)

Update `start(config:)` to build arguments from new fields:

```swift
var arguments = [
    "-m", "mlx_lm.server",
    "--model", config.model,
    "--max-tokens", String(config.maxTokens),
    "--port", String(config.port),
    "--prefill-step-size", String(config.prefillStepSize),
    "--prompt-cache-size", String(config.promptCacheSize),
    "--prompt-cache-bytes", String(config.promptCacheBytes)
]

if config.trustRemoteCode {
    arguments.append("--trust-remote-code")
}

arguments.append("--chat-template-args")
arguments.append("{\"enable_thinking\":\(config.enableThinking ? "true" : "false")}")

arguments.append(contentsOf: config.extraArgs)
```

### SettingsWindowController (Sources/MLXManagerApp/SettingsWindowController.swift)

Add new table columns:
- `port` - integer input
- `prefillStepSize` - integer input
- `promptCacheSize` - integer input
- `promptCacheBytes` - integer input
- `trustRemoteCode` - checkbox (display as "✓" or " ")
- `enableThinking` - checkbox (display as "✓" or " ")

Update `tableView(_:viewFor:)` and `cellEdited(_:)` to handle new fields.

### ConfigLoader (Sources/MLXManager/ConfigLoader.swift)

Add fields to `PresetDTO`:

```swift
private struct PresetDTO: Decodable {
    let name: String?
    let model: String?
    let maxTokens: Int?
    let port: Int?
    let prefillStepSize: Int?
    let promptCacheSize: Int?
    let promptCacheBytes: Int?
    let trustRemoteCode: Bool?
    let enableThinking: Bool?
    let extraArgs: [String]?
    let pythonPath: String?
}
```

Use optional chaining with defaults in `load(yaml:)`.

### presets.yaml

Update all presets with serve.sh parameters:

```yaml
presets:
  - name: "4-bit 40k"
    model: "mlx-community/Qwen3.5-35B-A3B-4bit"
    maxTokens: 40960
    port: 8081
    prefillStepSize: 4096
    promptCacheSize: 4
    promptCacheBytes: 10737418240
    trustRemoteCode: true
    enableThinking: false
    pythonPath: "~/.mlx-manager/venv/bin/python"
```

## Backward Compatibility

All new fields have defaults matching serve.sh values. Existing presets load with optimized defaults.

## Testing

1. Verify build succeeds
2. Test preset loading from YAML
3. Test UI table renders new columns
4. Verify server starts with correct arguments
5. Test boolean flags work correctly
