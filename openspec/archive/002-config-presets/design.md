# Design: Config Presets

## Data Model

```swift
/// A server configuration preset.
public struct ServerConfig: Equatable {
    public let name: String
    public let model: String
    public let maxTokens: Int
    public let extraArgs: [String]
}
```

`extraArgs` holds any additional CLI flags beyond `--model` and `--max-tokens` (e.g. `--trust-remote-code`, `--chat-template-args`).

## ConfigLoader

```swift
public enum ConfigLoader {
    /// Parse a YAML string into an array of ServerConfig presets.
    public static func load(yaml: String) throws -> [ServerConfig]
}
```

### YAML Format

```yaml
presets:
  - name: "4-bit 40k"
    model: "mlx-community/Qwen3.5-35B-A3B-4bit"
    maxTokens: 40960
    extraArgs:
      - "--trust-remote-code"
      - "--chat-template-args"
      - "{\"enable_thinking\":false}"
  - name: "4-bit 80k"
    model: "mlx-community/Qwen3.5-35B-A3B-4bit"
    maxTokens: 81920
    extraArgs:
      - "--trust-remote-code"
  - name: "8-bit 40k"
    model: "mlx-community/Qwen3.5-35B-A3B-8bit"
    maxTokens: 40960
    extraArgs:
      - "--trust-remote-code"
  - name: "8-bit 80k"
    model: "mlx-community/Qwen3.5-35B-A3B-8bit"
    maxTokens: 81920
    extraArgs:
      - "--trust-remote-code"
```

## YAML Parsing Strategy

Use `Foundation`'s `JSONSerialization` is not suitable for YAML. Options:

1. **Yams** (third-party SPM package) — mature, widely used Swift YAML parser.
2. **Manual line parsing** — fragile, not worth it for structured data.

Decision: **Use Yams via SPM**. It's the standard Swift YAML library and keeps the parser clean.

The YAML is decoded into `Codable` DTOs and then mapped to `ServerConfig`.

## Error Handling

```swift
public enum ConfigError: Error, Equatable {
    case invalidYAML
    case missingField(String)
}
```

## File Location

- Source: `Sources/MLXManager/ServerConfig.swift` (model)
- Source: `Sources/MLXManager/ConfigLoader.swift` (parser)
- Resource: `Resources/presets.yaml` (bundled YAML)
- Tests: `Tests/MLXManagerTests/ConfigLoaderTests.swift`
