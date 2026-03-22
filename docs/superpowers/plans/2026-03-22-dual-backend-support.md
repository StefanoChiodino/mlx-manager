# Dual-Backend Support (mlx-lm + mlx-vlm) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mlx-vlm as a first-class backend alongside mlx-lm, with per-backend venvs, correct arg assembly, backend-aware process scanning, and a settings UI that shows/hides fields based on the selected backend.

**Architecture:** A new `ServerArgBuilder` protocol with two implementations (`MLXLmArgBuilder`, `MLXVlmArgBuilder`) replaces the inline switch in `ServerManager.start()`. `ServerConfig` gains four VLM-specific fields and a `withResolvedPythonPath()` helper. `EnvironmentBootstrapper` becomes backend-aware (separate venvs). `ProcessScanner.findMLXServer()` is renamed to `findServer(backend:)` with dual detection patterns.

**Tech Stack:** Swift 5.9, XCTest/Swift Testing (`@Test`/`#expect`), AppKit, Yams (YAML), swift test for running tests.

**Run tests with:** `swift test`

**Spec:** `docs/superpowers/specs/2026-03-22-dual-backend-support-design.md`

---

## File Map

| File | Action | Responsibility |
| --- | --- | --- |
| `Sources/MLXManager/ServerConfig.swift` | Modify | Add 4 VLM fields + `withResolvedPythonPath()` |
| `Sources/MLXManager/ServerArgBuilder.swift` | **Create** | `ServerArgBuilder` protocol + `MLXLmArgBuilder` + `MLXVlmArgBuilder` |
| `Sources/MLXManager/ServerManager.swift` | Modify | Replace inline arg assembly with builder |
| `Sources/MLXManager/ProcessScanner.swift` | Modify | Rename `findMLXServer()` → `findServer(backend:)`, add VLM patterns |
| `Sources/MLXManager/EnvironmentBootstrapper.swift` | Modify | Add `backend` param, dual venv paths, remove shared-venv steps |
| `Sources/MLXManagerApp/EnvironmentInstaller.swift` | Modify | Update static `pythonPath`/`venvPath` to methods taking `ServerType` |
| `Sources/MLXManagerApp/AppDelegate.swift` | Modify | Use `withResolvedPythonPath()`, backend-aware bootstrap and scanner |
| `Sources/MLXManagerApp/SettingsWindowController.swift` | Modify | Backend segmented control, show/hide fields, backend column |
| `Sources/MLXManagerApp/presets.yaml` | Modify | Add VLM example presets |
| `Tests/MLXManagerTests/ServerManagerTests.swift` | Modify | Add arg builder tests for both backends |
| `Tests/MLXManagerTests/ProcessScannerTests.swift` | Modify | Migrate `findMLXServer()` → `findServer(backend:)`, add VLM + cross-contamination tests |
| `Tests/MLXManagerTests/ServerConfigCodableTests.swift` | Modify | Add VLM field round-trip, `withResolvedPythonPath()` tests |
| `Tests/MLXManagerTests/EnvironmentBootstrapperTests.swift` | Modify | Add backend-aware venv path tests |
| `docs/SPEC.md` | Modify | Update to reflect dual-backend reality |

---

## Task 1: Add VLM fields to `ServerConfig` and `withResolvedPythonPath()`

**Files:**

- Modify: `Sources/MLXManager/ServerConfig.swift`
- Modify: `Tests/MLXManagerTests/ServerConfigCodableTests.swift`

### Step 1.1: Write failing tests for VLM fields and `withResolvedPythonPath()`

Add to `Tests/MLXManagerTests/ServerConfigCodableTests.swift` (append to the file, inside the existing import/suite):

```swift
@Suite("ServerConfig VLM fields")
struct ServerConfigVLMFieldTests {

    @Test("VLM fields have correct defaults")
    func test_vlmFieldDefaults() {
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024, pythonPath: "/usr/bin/python3"
        )
        #expect(config.kvBits == 0)
        #expect(config.kvGroupSize == 64)
        #expect(config.maxKvSize == 0)
        #expect(config.quantizedKvStart == 0)
    }

    @Test("VLM fields round-trip through Codable")
    func test_vlmFieldsRoundTrip() throws {
        let original = ServerConfig(
            name: "vlm", model: "m", maxTokens: 0,
            kvBits: 4, kvGroupSize: 32, maxKvSize: 2048, quantizedKvStart: 100,
            pythonPath: "/p"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        #expect(decoded.kvBits == 4)
        #expect(decoded.kvGroupSize == 32)
        #expect(decoded.maxKvSize == 2048)
        #expect(decoded.quantizedKvStart == 100)
    }

    @Test("withResolvedPythonPath expands tilde")
    func test_withResolvedPythonPath_expandsTilde() {
        let config = ServerConfig(
            name: "t", model: "m", maxTokens: 1, pythonPath: "~/.mlx-manager/venv/bin/python"
        )
        let resolved = config.withResolvedPythonPath()
        #expect(!resolved.pythonPath.hasPrefix("~"))
        #expect(resolved.pythonPath.contains(".mlx-manager/venv/bin/python"))
    }

    @Test("withResolvedPythonPath is no-op for absolute path")
    func test_withResolvedPythonPath_absolutePath_unchanged() {
        let config = ServerConfig(
            name: "t", model: "m", maxTokens: 1, pythonPath: "/usr/bin/python3"
        )
        let resolved = config.withResolvedPythonPath()
        #expect(resolved.pythonPath == "/usr/bin/python3")
    }

    @Test("withResolvedPythonPath preserves all other fields")
    func test_withResolvedPythonPath_preservesAllFields() {
        let config = ServerConfig(
            name: "n", model: "mod", maxTokens: 99, port: 9999,
            prefillStepSize: 512, promptCacheSize: 3, promptCacheBytes: 5000,
            trustRemoteCode: true, enableThinking: true,
            extraArgs: ["--foo"], serverType: .mlxVLM,
            kvBits: 8, kvGroupSize: 16, maxKvSize: 1024, quantizedKvStart: 50,
            pythonPath: "~/.mlx-manager/venv-vlm/bin/python"
        )
        let resolved = config.withResolvedPythonPath()
        #expect(resolved.name == "n")
        #expect(resolved.model == "mod")
        #expect(resolved.maxTokens == 99)
        #expect(resolved.port == 9999)
        #expect(resolved.prefillStepSize == 512)
        #expect(resolved.promptCacheSize == 3)
        #expect(resolved.promptCacheBytes == 5000)
        #expect(resolved.trustRemoteCode == true)
        #expect(resolved.enableThinking == true)
        #expect(resolved.extraArgs == ["--foo"])
        #expect(resolved.serverType == .mlxVLM)
        #expect(resolved.kvBits == 8)
        #expect(resolved.kvGroupSize == 16)
        #expect(resolved.maxKvSize == 1024)
        #expect(resolved.quantizedKvStart == 50)
    }
}
```

- [ ] Add the tests above to `Tests/MLXManagerTests/ServerConfigCodableTests.swift`

### Step 1.2: Run tests — confirm they fail

```bash
swift test --filter ServerConfigVLMFieldTests
```

Expected: compile errors or test failures (fields don't exist yet).

- [ ] Run and confirm failure

### Step 1.3: Add VLM fields and `withResolvedPythonPath()` to `ServerConfig`

Replace `Sources/MLXManager/ServerConfig.swift` with:

```swift
import Foundation

/// Server type enum to choose between text-only and vision-language models.
public enum ServerType: String, Codable, CaseIterable {
    case mlxLM = "mlxLM"
    case mlxVLM = "mlxVLM"

    public var descriptiveName: String {
        switch self {
        case .mlxLM:  return "MLX-LM (text)"
        case .mlxVLM: return "MLX-VLM (vision)"
        }
    }

    public var serverModule: String { serverEntryName }

    public var serverEntryName: String {
        switch self {
        case .mlxLM:  return "mlx_lm.server"
        case .mlxVLM: return "mlx_vlm.server"
        }
    }
}

/// A server configuration preset.
public struct ServerConfig: Equatable, Codable {
    // Shared fields
    public let name: String
    public let model: String
    public let port: Int
    public let prefillStepSize: Int
    public let trustRemoteCode: Bool
    public let extraArgs: [String]
    public let serverType: ServerType
    public let pythonPath: String

    // mlx-lm only
    public let maxTokens: Int
    public let promptCacheSize: Int
    public let promptCacheBytes: Int
    public let enableThinking: Bool

    // mlx-vlm only (omitted from CLI args when at default/zero)
    public let kvBits: Int            // 0 = disabled (omit flag)
    public let kvGroupSize: Int       // only emitted when kvBits > 0
    public let maxKvSize: Int         // 0 = disabled (omit flag)
    public let quantizedKvStart: Int  // only emitted when kvBits > 0

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
        serverType: ServerType = .mlxLM,
        kvBits: Int = 0,
        kvGroupSize: Int = 64,
        maxKvSize: Int = 0,
        quantizedKvStart: Int = 0,
        pythonPath: String
    ) {
        self.name = name
        self.model = model
        self.maxTokens = maxTokens
        self.port = port
        self.prefillStepSize = prefillStepSize
        self.promptCacheSize = promptCacheSize
        self.promptCacheBytes = promptCacheBytes
        self.trustRemoteCode = trustRemoteCode
        self.enableThinking = enableThinking
        self.extraArgs = extraArgs
        self.serverType = serverType
        self.kvBits = kvBits
        self.kvGroupSize = kvGroupSize
        self.maxKvSize = maxKvSize
        self.quantizedKvStart = quantizedKvStart
        self.pythonPath = pythonPath
    }

    /// Returns a copy of this config with `pythonPath` tilde-expanded.
    /// All other fields are preserved exactly.
    public func withResolvedPythonPath() -> ServerConfig {
        let resolved = NSString(string: pythonPath).expandingTildeInPath
        guard resolved != pythonPath else { return self }
        return ServerConfig(
            name: name, model: model, maxTokens: maxTokens,
            port: port, prefillStepSize: prefillStepSize,
            promptCacheSize: promptCacheSize, promptCacheBytes: promptCacheBytes,
            trustRemoteCode: trustRemoteCode, enableThinking: enableThinking,
            extraArgs: extraArgs, serverType: serverType,
            kvBits: kvBits, kvGroupSize: kvGroupSize,
            maxKvSize: maxKvSize, quantizedKvStart: quantizedKvStart,
            pythonPath: resolved
        )
    }
}
```

- [ ] Replace `Sources/MLXManager/ServerConfig.swift` with the code above

### Step 1.4: Run tests — confirm they pass

```bash
swift test --filter ServerConfigVLMFieldTests
```

Expected: all 5 tests PASS.

- [ ] Run and confirm pass

### Step 1.5: Run full test suite — fix any regressions

```bash
swift test
```

Any tests that were constructing `ServerConfig` without the new fields will still compile (all new params have defaults). Fix any that break.

- [ ] Run and confirm all tests pass

### Step 1.6: Commit

```bash
git add Sources/MLXManager/ServerConfig.swift Tests/MLXManagerTests/ServerConfigCodableTests.swift
git commit -m "feat: add VLM fields and withResolvedPythonPath() to ServerConfig"
```

- [ ] Commit

---

## Task 2: `ServerArgBuilder` — protocol and two implementations

**Files:**

- Create: `Sources/MLXManager/ServerArgBuilder.swift`
- Modify: `Tests/MLXManagerTests/ServerManagerTests.swift`

### Step 2.1: Write failing tests for `MLXLmArgBuilder`

Append to `Tests/MLXManagerTests/ServerManagerTests.swift`:

```swift
// MARK: - MLXLmArgBuilder

@Suite("MLXLmArgBuilder")
struct MLXLmArgBuilderTests {

    func makeConfig(
        model: String = "mlx-community/Qwen3-4bit",
        maxTokens: Int = 40960,
        port: Int = 8081,
        prefillStepSize: Int = 4096,
        promptCacheSize: Int = 4,
        promptCacheBytes: Int = 10 * 1024 * 1024 * 1024,
        trustRemoteCode: Bool = false,
        enableThinking: Bool = false,
        extraArgs: [String] = [],
        pythonPath: String = "/venv/bin/python"
    ) -> ServerConfig {
        ServerConfig(
            name: "test", model: model, maxTokens: maxTokens,
            port: port, prefillStepSize: prefillStepSize,
            promptCacheSize: promptCacheSize, promptCacheBytes: promptCacheBytes,
            trustRemoteCode: trustRemoteCode, enableThinking: enableThinking,
            extraArgs: extraArgs, serverType: .mlxLM, pythonPath: pythonPath
        )
    }

    @Test("emits module, model, max-tokens, port, prefill, cache-size, cache-bytes")
    func test_lm_coreArgs() {
        let config = makeConfig()
        let args = MLXLmArgBuilder().arguments(for: config)
        #expect(args.contains("-m"))
        #expect(args.contains("mlx_lm.server"))
        #expect(args.contains("--model"))
        #expect(args.contains("--max-tokens"))
        #expect(args.contains("--port"))
        #expect(args.contains("--prefill-step-size"))
        #expect(args.contains("--prompt-cache-size"))
        #expect(args.contains("--prompt-cache-bytes"))
    }

    @Test("always emits --chat-template-args with enable_thinking:false")
    func test_lm_chatTemplateArgs_false() {
        let config = makeConfig(enableThinking: false)
        let args = MLXLmArgBuilder().arguments(for: config)
        #expect(args.contains("--chat-template-args"))
        let idx = args.firstIndex(of: "--chat-template-args")!
        #expect(args[idx + 1] == "{\"enable_thinking\":false}")
    }

    @Test("emits --chat-template-args with enable_thinking:true when enableThinking is true")
    func test_lm_chatTemplateArgs_true() {
        let config = makeConfig(enableThinking: true)
        let args = MLXLmArgBuilder().arguments(for: config)
        let idx = args.firstIndex(of: "--chat-template-args")!
        #expect(args[idx + 1] == "{\"enable_thinking\":true}")
    }

    @Test("omits --trust-remote-code when false")
    func test_lm_trustRemoteCode_omittedWhenFalse() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(trustRemoteCode: false))
        #expect(!args.contains("--trust-remote-code"))
    }

    @Test("includes --trust-remote-code when true")
    func test_lm_trustRemoteCode_includedWhenTrue() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(trustRemoteCode: true))
        #expect(args.contains("--trust-remote-code"))
    }

    @Test("appends extraArgs at end")
    func test_lm_extraArgs() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(extraArgs: ["--foo", "bar"]))
        #expect(args.suffix(2) == ["--foo", "bar"])
    }

    @Test("full argument list matches expected exactly")
    func test_lm_fullArgList() {
        let config = ServerConfig(
            name: "t", model: "mlx-community/Qwen3-4bit", maxTokens: 40960,
            port: 8081, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10_737_418_240,
            trustRemoteCode: true, enableThinking: false,
            extraArgs: [], serverType: .mlxLM,
            pythonPath: "/venv/bin/python"
        )
        let args = MLXLmArgBuilder().arguments(for: config)
        #expect(args == [
            "-m", "mlx_lm.server",
            "--model", "mlx-community/Qwen3-4bit",
            "--max-tokens", "40960",
            "--port", "8081",
            "--prefill-step-size", "4096",
            "--prompt-cache-size", "4",
            "--prompt-cache-bytes", "10737418240",
            "--trust-remote-code",
            "--chat-template-args", "{\"enable_thinking\":false}"
        ])
    }
}

// MARK: - MLXVlmArgBuilder

@Suite("MLXVlmArgBuilder")
struct MLXVlmArgBuilderTests {

    func makeConfig(
        model: String = "mlx-community/Qwen2.5-VL-7B-4bit",
        port: Int = 8082,
        prefillStepSize: Int = 512,
        trustRemoteCode: Bool = false,
        extraArgs: [String] = [],
        kvBits: Int = 0,
        kvGroupSize: Int = 64,
        maxKvSize: Int = 0,
        quantizedKvStart: Int = 0
    ) -> ServerConfig {
        ServerConfig(
            name: "vlm", model: model, maxTokens: 0,
            port: port, prefillStepSize: prefillStepSize,
            trustRemoteCode: trustRemoteCode,
            extraArgs: extraArgs, serverType: .mlxVLM,
            kvBits: kvBits, kvGroupSize: kvGroupSize,
            maxKvSize: maxKvSize, quantizedKvStart: quantizedKvStart,
            pythonPath: "/venv-vlm/bin/python"
        )
    }

    @Test("emits module, model, port, prefill")
    func test_vlm_coreArgs() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig())
        #expect(args.contains("-m"))
        #expect(args.contains("mlx_vlm.server"))
        #expect(args.contains("--model"))
        #expect(args.contains("--port"))
        #expect(args.contains("--prefill-step-size"))
    }

    @Test("does NOT emit --max-tokens, --prompt-cache-size, --chat-template-args")
    func test_vlm_noLMOnlyArgs() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig())
        #expect(!args.contains("--max-tokens"))
        #expect(!args.contains("--prompt-cache-size"))
        #expect(!args.contains("--prompt-cache-bytes"))
        #expect(!args.contains("--chat-template-args"))
    }

    @Test("omits kv-bits, kv-group-size, quantized-kv-start when kvBits == 0")
    func test_vlm_kvBitsZero_omitsKVFlags() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(kvBits: 0))
        #expect(!args.contains("--kv-bits"))
        #expect(!args.contains("--kv-group-size"))
        #expect(!args.contains("--quantized-kv-start"))
    }

    @Test("emits kv-bits, kv-group-size, quantized-kv-start when kvBits > 0")
    func test_vlm_kvBitsNonZero_emitsKVFlags() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(kvBits: 4, kvGroupSize: 32, quantizedKvStart: 10))
        #expect(args.contains("--kv-bits"))
        let bitsIdx = args.firstIndex(of: "--kv-bits")!
        #expect(args[bitsIdx + 1] == "4")
        #expect(args.contains("--kv-group-size"))
        let groupIdx = args.firstIndex(of: "--kv-group-size")!
        #expect(args[groupIdx + 1] == "32")
        #expect(args.contains("--quantized-kv-start"))
        let startIdx = args.firstIndex(of: "--quantized-kv-start")!
        #expect(args[startIdx + 1] == "10")
    }

    @Test("omits --max-kv-size when maxKvSize == 0")
    func test_vlm_maxKvSizeZero_omitFlag() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(maxKvSize: 0))
        #expect(!args.contains("--max-kv-size"))
    }

    @Test("emits --max-kv-size when maxKvSize > 0")
    func test_vlm_maxKvSizeNonZero_emitFlag() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(maxKvSize: 2048))
        #expect(args.contains("--max-kv-size"))
        let idx = args.firstIndex(of: "--max-kv-size")!
        #expect(args[idx + 1] == "2048")
    }

    @Test("appends extraArgs at end")
    func test_vlm_extraArgs() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(extraArgs: ["--foo", "bar"]))
        #expect(args.suffix(2) == ["--foo", "bar"])
    }

    @Test("full argument list, all defaults")
    func test_vlm_fullArgListDefaults() {
        let config = ServerConfig(
            name: "v", model: "mlx-community/Qwen2.5-VL-7B-4bit", maxTokens: 0,
            port: 8082, prefillStepSize: 512,
            serverType: .mlxVLM, pythonPath: "/p"
        )
        let args = MLXVlmArgBuilder().arguments(for: config)
        #expect(args == [
            "-m", "mlx_vlm.server",
            "--model", "mlx-community/Qwen2.5-VL-7B-4bit",
            "--port", "8082",
            "--prefill-step-size", "512"
        ])
    }
}
```

- [ ] Append the tests above to `Tests/MLXManagerTests/ServerManagerTests.swift`

### Step 2.2: Run tests — confirm they fail

```bash
swift test --filter MLXLmArgBuilderTests
swift test --filter MLXVlmArgBuilderTests
```

Expected: compile errors (`MLXLmArgBuilder` and `MLXVlmArgBuilder` don't exist yet).

- [ ] Run and confirm failure

### Step 2.3: Create `Sources/MLXManager/ServerArgBuilder.swift`

```swift
import Foundation

/// Assembles CLI arguments for a specific server backend.
public protocol ServerArgBuilder {
    func arguments(for config: ServerConfig) -> [String]
}

// MARK: - MLX-LM

/// Builds arguments for `mlx_lm.server`.
public struct MLXLmArgBuilder: ServerArgBuilder {
    public init() {}

    public func arguments(for config: ServerConfig) -> [String] {
        var args: [String] = [
            "-m", "mlx_lm.server",
            "--model", config.model,
            "--max-tokens", String(config.maxTokens),
            "--port", String(config.port),
            "--prefill-step-size", String(config.prefillStepSize),
            "--prompt-cache-size", String(config.promptCacheSize),
            "--prompt-cache-bytes", String(config.promptCacheBytes)
        ]
        if config.trustRemoteCode {
            args.append("--trust-remote-code")
        }
        // Always emitted — mlx-lm accepts this for all models.
        args.append("--chat-template-args")
        args.append("{\"enable_thinking\":\(config.enableThinking ? "true" : "false")}")
        args.append(contentsOf: config.extraArgs)
        return args
    }
}

// MARK: - MLX-VLM

/// Builds arguments for `mlx_vlm.server`.
public struct MLXVlmArgBuilder: ServerArgBuilder {
    public init() {}

    public func arguments(for config: ServerConfig) -> [String] {
        var args: [String] = [
            "-m", "mlx_vlm.server",
            "--model", config.model,
            "--port", String(config.port),
            "--prefill-step-size", String(config.prefillStepSize)
        ]
        if config.trustRemoteCode {
            args.append("--trust-remote-code")
        }
        // KV quantisation flags — only meaningful when kvBits > 0.
        if config.kvBits > 0 {
            args.append(contentsOf: ["--kv-bits", String(config.kvBits)])
            args.append(contentsOf: ["--kv-group-size", String(config.kvGroupSize)])
            args.append(contentsOf: ["--quantized-kv-start", String(config.quantizedKvStart)])
        }
        if config.maxKvSize > 0 {
            args.append(contentsOf: ["--max-kv-size", String(config.maxKvSize)])
        }
        args.append(contentsOf: config.extraArgs)
        return args
    }
}
```

- [ ] Create `Sources/MLXManager/ServerArgBuilder.swift` with the code above

### Step 2.4: Run tests — confirm they pass

```bash
swift test --filter MLXLmArgBuilderTests
swift test --filter MLXVlmArgBuilderTests
```

Expected: all tests PASS.

- [ ] Run and confirm pass

### Step 2.5: Run full suite

```bash
swift test
```

- [ ] All tests pass

### Step 2.6: Commit

```bash
git add Sources/MLXManager/ServerArgBuilder.swift Tests/MLXManagerTests/ServerManagerTests.swift
git commit -m "feat: add ServerArgBuilder protocol with MLXLmArgBuilder and MLXVlmArgBuilder"
```

- [ ] Commit

---

## Task 3: Wire builders into `ServerManager` — replace inline arg assembly

**Files:**

- Modify: `Sources/MLXManager/ServerManager.swift`
- Modify: `Tests/MLXManagerTests/ServerManagerTests.swift`

### Step 3.1: Add a test that will genuinely fail before the refactor

> **Context for the implementer:** The existing `ServerManager.start()` already has a `switch config.serverType` that emits `mlx_vlm.server` and suppresses `--max-tokens` and `--chat-template-args` for VLM. A simple "contains mlx_vlm.server" test would already pass against the current code. We need a test that targets behaviour the builder introduces that the current inline switch **cannot** produce: specifically, respecting the new `kvBits` field. The current code never emits `--kv-bits` at all.

Add to `Tests/MLXManagerTests/ServerManagerTests.swift`:

```swift
@Test("start emits --kv-bits for VLM config with kvBits > 0")
func test_start_vlm_emitsKvBits() throws {
    let launcher = MockLauncher()
    let manager = ServerManager(launcher: launcher)
    let config = ServerConfig(
        name: "vlm", model: "mlx-community/Qwen2.5-VL-7B-4bit",
        maxTokens: 0, port: 8082, prefillStepSize: 512,
        serverType: .mlxVLM,
        kvBits: 4, kvGroupSize: 32, quantizedKvStart: 0,
        pythonPath: "/venv-vlm/bin/python"
    )
    try manager.start(config: config)
    let args = launcher.launchedArguments ?? []
    #expect(args.contains("--kv-bits"))
    let idx = args.firstIndex(of: "--kv-bits")!
    #expect(args[idx + 1] == "4")
    #expect(args.contains("--kv-group-size"))
}
```

- [ ] Add the test above to `Tests/MLXManagerTests/ServerManagerTests.swift`

### Step 3.2: Run the new test — confirm it fails

```bash
swift test --filter "test_start_vlm_emitsKvBits"
```

Expected: FAIL — the current `ServerManager.start()` inline switch never emits `--kv-bits`.

- [ ] Run and confirm failure

### Step 3.3: Replace inline arg assembly in `ServerManager.start()`

In `Sources/MLXManager/ServerManager.swift`, replace the `start(config:)` method body. The entire `var arguments` block (everything up to `process = try launcher.launch(...)`) should become:

```swift
public func start(config: ServerConfig) throws {
    if isRunning { throw ServerError.alreadyRunning }

    let builder: ServerArgBuilder = config.serverType == .mlxLM
        ? MLXLmArgBuilder() : MLXVlmArgBuilder()
    let arguments = builder.arguments(for: config)

    process = try launcher.launch(command: config.pythonPath, arguments: arguments, logPath: logPath) { [weak self] in
        self?.process = nil
        self?.onExit?()
    }
}
```

- [ ] Update `ServerManager.start()` to use the builder

### Step 3.4: Run tests — confirm they pass

```bash
swift test --filter ServerManagerTests
```

Expected: all existing + new tests PASS.

- [ ] Run and confirm pass

### Step 3.5: Run full suite

```bash
swift test
```

- [ ] All tests pass

### Step 3.6: Commit

```bash
git add Sources/MLXManager/ServerManager.swift Tests/MLXManagerTests/ServerManagerTests.swift
git commit -m "refactor: replace inline arg assembly in ServerManager with ServerArgBuilder"
```

- [ ] Commit

---

## Task 4: `ProcessScanner` — rename and add VLM detection

**Files:**

- Modify: `Sources/MLXManager/ProcessScanner.swift`
- Modify: `Tests/MLXManagerTests/ProcessScannerTests.swift`

### Step 4.1: Write failing tests for VLM detection and cross-contamination

Append to `Tests/MLXManagerTests/ProcessScannerTests.swift`:

```swift
@Suite("ProcessScanner - findServer(backend:)")
struct ProcessScannerBackendTests {

    // VLM detection tests

    @Test("VLM: -m mlx_vlm.server detected")
    func test_findServer_vlm_moduleFlag() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([10]),
            argvReader: StubProcessArgvReader([
                10: ["/venv/bin/python", "-m", "mlx_vlm.server", "--port", "8082"]
            ])
        )
        #expect(scanner.findServer(backend: .mlxVLM) == DiscoveredProcess(pid: 10, port: 8082))
    }

    @Test("VLM: bare mlx_vlm.server element detected")
    func test_findServer_vlm_bareElement() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([11]),
            argvReader: StubProcessArgvReader([
                11: ["mlx_vlm.server", "--port", "8082"]
            ])
        )
        #expect(scanner.findServer(backend: .mlxVLM) == DiscoveredProcess(pid: 11, port: 8082))
    }

    @Test("VLM: path ending in mlx_vlm/server.py detected")
    func test_findServer_vlm_scriptPath() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([12]),
            argvReader: StubProcessArgvReader([
                12: ["/python3", "/site-packages/mlx_vlm/server.py", "--port", "8082"]
            ])
        )
        #expect(scanner.findServer(backend: .mlxVLM) == DiscoveredProcess(pid: 12, port: 8082))
    }

    @Test("VLM: path ending in /mlx_vlm.server detected")
    func test_findServer_vlm_venvBinScript() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([13]),
            argvReader: StubProcessArgvReader([
                13: ["/python3", "/venv-vlm/bin/mlx_vlm.server", "--port", "8082"]
            ])
        )
        #expect(scanner.findServer(backend: .mlxVLM) == DiscoveredProcess(pid: 13, port: 8082))
    }

    // Cross-contamination tests

    @Test("LM backend does NOT match VLM process")
    func test_findServer_lm_doesNotMatchVLMProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([20]),
            argvReader: StubProcessArgvReader([
                20: ["/python3", "-m", "mlx_vlm.server", "--port", "8082"]
            ])
        )
        #expect(scanner.findServer(backend: .mlxLM) == nil)
    }

    @Test("VLM backend does NOT match LM process")
    func test_findServer_vlm_doesNotMatchLMProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([21]),
            argvReader: StubProcessArgvReader([
                21: ["/python3", "-m", "mlx_lm.server", "--port", "8081"]
            ])
        )
        #expect(scanner.findServer(backend: .mlxVLM) == nil)
    }
}
```

- [ ] Append tests above to `Tests/MLXManagerTests/ProcessScannerTests.swift`

### Step 4.2: Run tests — confirm they fail

```bash
swift test --filter ProcessScannerBackendTests
```

Expected: compile errors or failures (`findServer(backend:)` doesn't exist yet).

- [ ] Run and confirm failure

### Step 4.3: Update `ProcessScanner` — rename method and add VLM patterns

Replace `Sources/MLXManager/ProcessScanner.swift` with:

```swift
import Foundation
import Darwin

/// A running mlx server process found by the scanner.
public struct DiscoveredProcess: Equatable {
    public let pid: Int32
    public let port: Int

    public init(pid: Int32, port: Int) {
        self.pid = pid
        self.port = port
    }
}

/// Returns all PIDs currently running on the system.
public protocol PIDListing {
    func allPIDs() -> [Int32]
}

/// Reads the argument vector of a running process by PID.
public protocol ProcessArgvReading {
    func argv(for pid: Int32) -> [String]?
}

/// Production implementation of PIDListing using proc_listallpids.
public struct SystemPIDLister: PIDListing {
    public init() {}

    public func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 16)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled)).filter { $0 > 0 })
    }
}

/// Production implementation that reads process argv via sysctl(KERN_PROCARGS2).
public struct SystemProcessArgvReader: ProcessArgvReading {
    public init() {}

    public func argv(for pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        guard size > 4 else { return nil }
        var offset = 4
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }
        var args: [String] = []
        var start = offset
        while offset < size {
            if buffer[offset] == 0 {
                if offset > start {
                    let slice = Array(buffer[start..<offset])
                    if let s = String(bytes: slice, encoding: .utf8) { args.append(s) }
                }
                start = offset + 1
            }
            offset += 1
        }
        if start < size {
            let slice = Array(buffer[start..<size])
            if let s = String(bytes: slice, encoding: .utf8), !s.isEmpty { args.append(s) }
        }
        return args.isEmpty ? nil : args
    }
}

/// Scans all running processes and returns the first one identified as
/// a server matching the given backend.
public struct ProcessScanner {
    private let pidLister: PIDListing
    private let argvReader: ProcessArgvReading

    public init(pidLister: PIDListing, argvReader: ProcessArgvReading) {
        self.pidLister = pidLister
        self.argvReader = argvReader
    }

    /// Returns the first discovered server process for the given backend, or nil.
    public func findServer(backend: ServerType) -> DiscoveredProcess? {
        for pid in pidLister.allPIDs() {
            guard let args = argvReader.argv(for: pid) else { continue }
            guard isServer(args, backend: backend) else { continue }
            return DiscoveredProcess(pid: pid, port: extractPort(from: args))
        }
        return nil
    }

    private func isServer(_ args: [String], backend: ServerType) -> Bool {
        let module = backend.serverEntryName  // e.g. "mlx_lm.server" or "mlx_vlm.server"
        // Strip dots for path suffix matching: "mlx_lm/server.py" or "mlx_vlm/server.py"
        let pathComponent = module.replacingOccurrences(of: ".", with: "/") + ".py"
        // e.g. "mlx_lm/server.py" or "mlx_vlm/server.py"

        if let idx = args.firstIndex(of: "-m"),
           args.indices.contains(idx + 1),
           args[idx + 1] == module { return true }
        if args.contains(module) { return true }
        if args.contains(where: { $0.hasSuffix(pathComponent) }) { return true }
        // venv bin script: ends in /mlx_lm.server or /mlx_vlm.server
        if args.contains(where: { $0.hasSuffix("/\(module)") }) { return true }
        return false
    }

    private func extractPort(from args: [String]) -> Int {
        if let idx = args.firstIndex(of: "--port"),
           args.indices.contains(idx + 1),
           let port = Int(args[idx + 1]) { return port }
        return 8080
    }
}
```

- [ ] Replace `Sources/MLXManager/ProcessScanner.swift` with the code above

### Step 4.4: Migrate existing `findMLXServer()` test calls to `findServer(backend: .mlxLM)`

In `Tests/MLXManagerTests/ProcessScannerTests.swift`, replace every `scanner.findMLXServer()` with `scanner.findServer(backend: .mlxLM)`.

- [ ] Do the rename (12 call sites — use find-and-replace)

### Step 4.5: Run tests — confirm they pass

```bash
swift test --filter ProcessScannerTests
swift test --filter ProcessScannerBackendTests
```

Expected: all tests PASS.

- [ ] Run and confirm pass

### Step 4.6: Run full suite

```bash
swift test
```

- [ ] All tests pass

### Step 4.7: Commit

```bash
git add Sources/MLXManager/ProcessScanner.swift Tests/MLXManagerTests/ProcessScannerTests.swift
git commit -m "feat: add findServer(backend:) with VLM detection and cross-contamination isolation"
```

- [ ] Commit

---

## Task 5: Backend-aware `EnvironmentBootstrapper` and `EnvironmentInstaller`

**Files:**

- Modify: `Sources/MLXManager/EnvironmentBootstrapper.swift`
- Modify: `Sources/MLXManagerApp/EnvironmentInstaller.swift`
- Modify: `Tests/MLXManagerTests/EnvironmentBootstrapperTests.swift`

### Step 5.1: Write failing tests for backend-aware paths

Append to `Tests/MLXManagerTests/EnvironmentBootstrapperTests.swift`:

```swift
@Suite("EnvironmentBootstrapper - backend venv paths")
struct EnvironmentBootstrapperBackendTests {

    @Test("pythonPath for mlxLM returns lm venv")
    func test_pythonPath_lm() {
        let path = EnvironmentBootstrapper.pythonPath(for: .mlxLM)
        #expect(path.contains(".mlx-manager/venv/bin/python"))
        #expect(!path.contains("venv-vlm"))
    }

    @Test("pythonPath for mlxVLM returns vlm venv")
    func test_pythonPath_vlm() {
        let path = EnvironmentBootstrapper.pythonPath(for: .mlxVLM)
        #expect(path.contains(".mlx-manager/venv-vlm/bin/python"))
    }

    @Test("venvPath for mlxLM returns lm venv directory")
    func test_venvPath_lm() {
        let path = EnvironmentBootstrapper.venvPath(for: .mlxLM)
        #expect(path.contains(".mlx-manager/venv"))
        #expect(!path.contains("venv-vlm"))
    }

    @Test("venvPath for mlxVLM returns vlm venv directory")
    func test_venvPath_vlm() {
        let path = EnvironmentBootstrapper.venvPath(for: .mlxVLM)
        #expect(path.contains(".mlx-manager/venv-vlm"))
    }

    @Test("LM install uses mlx-lm package and never installs mlx-vlm")
    func test_install_lm_usesMLXLmPackage() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            backend: .mlxLM,
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy
        )
        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }
        // Use filter to catch all pip calls — if the impl emits multiple pip steps,
        // we must verify NONE of them install mlx-vlm.
        let allPipCalls = spy.calls.filter { $0.arguments.first == "pip" }
        #expect(allPipCalls.contains(where: { $0.arguments.contains("mlx-lm") }), "expected at least one pip install mlx-lm call")
        #expect(!allPipCalls.contains(where: { $0.arguments.contains("mlx-vlm") }), "LM bootstrapper must not install mlx-vlm")
    }

    @Test("VLM install uses mlx-vlm package and never installs mlx-lm")
    func test_install_vlm_usesMLXVlmPackage() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            backend: .mlxVLM,
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy
        )
        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }
        let allPipCalls = spy.calls.filter { $0.arguments.first == "pip" }
        #expect(allPipCalls.contains(where: { $0.arguments.contains("mlx-vlm") }), "expected at least one pip install mlx-vlm call")
        #expect(!allPipCalls.contains(where: { $0.arguments.contains("mlx-lm") }), "VLM bootstrapper must not install mlx-lm")
    }
}
```

- [ ] Append tests above to `Tests/MLXManagerTests/EnvironmentBootstrapperTests.swift`

### Step 5.2: Run tests — confirm they fail

```bash
swift test --filter EnvironmentBootstrapperBackendTests
```

Expected: compile errors or failures.

- [ ] Run and confirm failure

### Step 5.3: Update `EnvironmentBootstrapper` — add `backend` param, separate venvs

> **Note for implementer:** The existing tests in `EnvironmentBootstrapperTests` call `EnvironmentBootstrapper(uvLocator:runner:uvInstallCommand:)` — no `backend` param. After you add `backend` as the first parameter (with a default of `.mlxLM`), all existing call sites will continue to compile unchanged because of the default. Verify this after replacing the file.

Replace `Sources/MLXManager/EnvironmentBootstrapper.swift` with:

```swift
import Foundation

/// Bootstraps the managed Python environment using `uv`.
///
/// Each backend gets its own venv:
/// - mlxLM:  ~/.mlx-manager/venv      (installs mlx-lm)
/// - mlxVLM: ~/.mlx-manager/venv-vlm  (installs mlx-vlm)
public final class EnvironmentBootstrapper {

    public var onOutput: ((String) -> Void)?
    public var onComplete: ((Bool) -> Void)?

    private let backend: ServerType
    private let uvLocator: UVLocator
    private let runner: CommandRunner
    private let uvInstallCommand: (() -> Bool)?

    public static func venvPath(for backend: ServerType) -> String {
        switch backend {
        case .mlxLM:  return NSString("~/.mlx-manager/venv").expandingTildeInPath
        case .mlxVLM: return NSString("~/.mlx-manager/venv-vlm").expandingTildeInPath
        }
    }

    public static func pythonPath(for backend: ServerType) -> String {
        venvPath(for: backend) + "/bin/python"
    }

    // Legacy accessors (mlxLM defaults) for backwards compatibility
    public static var venvPath: String { venvPath(for: .mlxLM) }
    public static var pythonPath: String { pythonPath(for: .mlxLM) }

    public init(
        backend: ServerType = .mlxLM,
        uvLocator: UVLocator = UVLocator(),
        runner: CommandRunner,
        uvInstallCommand: (() -> Bool)? = nil
    ) {
        self.backend = backend
        self.uvLocator = uvLocator
        self.runner = runner
        self.uvInstallCommand = uvInstallCommand
    }

    public func install() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.runInstall()
        }
    }

    // MARK: - Private

    private func runInstall() {
        guard let uvPath = resolveUV() else {
            emit("Error: could not locate or install uv\n")
            DispatchQueue.main.async { self.onComplete?(false) }
            return
        }

        let venv = Self.venvPath(for: backend)
        let python = Self.pythonPath(for: backend)
        let package = backend == .mlxLM ? "mlx-lm" : "mlx-vlm"

        let venvOK = step(uvPath, ["venv", venv, "--python", "3.12"], label: "Creating venv…")
        guard venvOK else {
            DispatchQueue.main.async { self.onComplete?(false) }
            return
        }

        let installOK = step(uvPath, ["pip", "install", package, "--python", python],
                             label: "Installing \(package)…")
        DispatchQueue.main.async { self.onComplete?(installOK) }
    }

    private func resolveUV() -> String? {
        if let path = uvLocator.locate() { return path }
        emit("uv not found. Installing uv…\n")
        let installer = uvInstallCommand ?? defaultUVInstaller
        guard installer() else { return nil }
        return uvLocator.locate()
    }

    private func defaultUVInstaller() -> Bool {
        emit("Running: curl -LsSf https://astral.sh/uv/install.sh | sh\n")
        let code = runner.run(
            command: "/bin/sh",
            arguments: ["-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"],
            onOutput: { [weak self] in self?.emit($0) }
        )
        return code == 0
    }

    private func step(_ command: String, _ arguments: [String], label: String) -> Bool {
        emit(label + "\n")
        let code = runner.run(command: command, arguments: arguments,
                              onOutput: { [weak self] in self?.emit($0) })
        return code == 0
    }

    private func emit(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onOutput?(text) }
    }
}
```

- [ ] Replace `Sources/MLXManager/EnvironmentBootstrapper.swift` with the code above

### Step 5.4: Update `EnvironmentInstaller` — forward `backend` to bootstrapper

Replace `Sources/MLXManagerApp/EnvironmentInstaller.swift` with:

```swift
import Foundation
import MLXManager

/// Thin adapter: public API for the app layer, delegates to `EnvironmentBootstrapper`.
final class EnvironmentInstaller {

    static func venvPath(for backend: ServerType) -> String {
        EnvironmentBootstrapper.venvPath(for: backend)
    }

    static func pythonPath(for backend: ServerType) -> String {
        EnvironmentBootstrapper.pythonPath(for: backend)
    }

    // Legacy (mlxLM default) for any call sites not yet updated
    static var venvPath: String { venvPath(for: .mlxLM) }
    static var pythonPath: String { pythonPath(for: .mlxLM) }

    var onOutput: ((String) -> Void)? {
        didSet { bootstrapper.onOutput = onOutput }
    }
    var onComplete: ((Bool) -> Void)? {
        didSet { bootstrapper.onComplete = onComplete }
    }

    private let bootstrapper: EnvironmentBootstrapper

    init(backend: ServerType = .mlxLM) {
        bootstrapper = EnvironmentBootstrapper(backend: backend, runner: ProcessCommandRunner())
    }

    func install() { bootstrapper.install() }

    func cancel() {
        bootstrapper.onComplete = nil
        bootstrapper.onOutput = nil
    }
}
```

- [ ] Replace `Sources/MLXManagerApp/EnvironmentInstaller.swift` with the code above

### Step 5.5: Run tests — confirm they pass

```bash
swift test --filter EnvironmentBootstrapperTests
swift test --filter EnvironmentBootstrapperBackendTests
```

Expected: all PASS.

- [ ] Run and confirm pass

### Step 5.6: Run full suite

```bash
swift test
```

- [ ] All tests pass

### Step 5.7: Commit

```bash
git add Sources/MLXManager/EnvironmentBootstrapper.swift Sources/MLXManagerApp/EnvironmentInstaller.swift Tests/MLXManagerTests/EnvironmentBootstrapperTests.swift
git commit -m "feat: backend-aware EnvironmentBootstrapper with separate venvs per backend"
```

- [ ] Commit

---

## Task 6: Update `AppDelegate` call sites

**Files:**

- Modify: `Sources/MLXManagerApp/AppDelegate.swift`

> **Known limitation:** `recoverRunningServer()` uses `presets.first?.serverType` to decide which backend to scan for. If the user has VLM presets listed first but an LM server running, recovery will miss it. This is an intentional simplification — multi-backend recovery is out of scope.

### Step 6.0: Add regression test for `resolvedPythonPath` field-dropping bug

> **Context:** The current `AppDelegate.resolvedPythonPath(_:)` silently drops `port`, `prefillStepSize`, `promptCacheSize`, `promptCacheBytes`, `trustRemoteCode`, `enableThinking`, `serverType`, and all VLM fields when reconstructing `ServerConfig`. This has always been a latent bug; adding VLM fields makes it critical. Write a test that exposes this before we fix it.

Add to `Tests/MLXManagerTests/ServerConfigCodableTests.swift` (in the `ServerConfigVLMFieldTests` suite):

```swift
@Test("withResolvedPythonPath preserves serverType and port (regression: old resolvedPythonPath dropped them)")
func test_withResolvedPythonPath_preservesServerTypeAndPort() {
    let config = ServerConfig(
        name: "t", model: "m", maxTokens: 100,
        port: 9999,
        serverType: .mlxVLM,
        kvBits: 4,
        pythonPath: "~/.mlx-manager/venv-vlm/bin/python"
    )
    let resolved = config.withResolvedPythonPath()
    #expect(resolved.port == 9999)
    #expect(resolved.serverType == .mlxVLM)
    #expect(resolved.kvBits == 4)
}
```

This test already passes once `withResolvedPythonPath()` is implemented (Task 1), but it documents the regression that the old approach had and confirms the fix is correct.

- [ ] Add regression test above to `Tests/MLXManagerTests/ServerConfigCodableTests.swift`

### Step 6.1: Replace `resolvedPythonPath(_:)` with `withResolvedPythonPath()`

Find `AppDelegate.resolvedPythonPath(_:)` (around line 294) and its two call sites.

Replace all three with uses of `config.withResolvedPythonPath()`:

```swift
// Before:
let resolvedConfig = resolvedPythonPath(config)

// After:
let resolvedConfig = config.withResolvedPythonPath()
```

And in `loadPresets()` (around line 259):
```swift
// Before:
return presets.map { resolvedPythonPath($0) }

// After:
return presets.map { $0.withResolvedPythonPath() }
```

Delete the private `resolvedPythonPath(_:)` method entirely.

- [ ] Replace `resolvedPythonPath` usage with `withResolvedPythonPath()` and delete the old method

### Step 6.2: Update `recoverRunningServer()` to pass backend

The method scans for a running server. It needs to know which backend to look for. Use the first preset's `serverType` (defaulting to `.mlxLM`):

```swift
private func recoverRunningServer() {
    let scanner = ProcessScanner(
        pidLister: SystemPIDLister(),
        argvReader: SystemProcessArgvReader()
    )
    let backend = presets.first?.serverType ?? .mlxLM
    guard let found = scanner.findServer(backend: backend) else { return }
    try? serverManager.adoptProcess(pid: found.pid, port: found.port)
    serverState = ServerState()
    serverState.serverStarted()
    statusBarController.serverDidStart()
    startTailing()
    if settings.ramGraphEnabled {
        startRAMPolling(pid: found.pid)
    }
}
```

- [ ] Update `recoverRunningServer()` as above

### Step 6.3: Update `bootstrapEnvironmentIfNeeded()` to use active preset's backend

```swift
private func bootstrapEnvironmentIfNeeded() {
    let backend = presets.first?.serverType ?? .mlxLM
    let pythonPath = EnvironmentInstaller.pythonPath(for: backend)
    let checker = EnvironmentChecker()
    guard !checker.isReady(pythonPath: pythonPath) else { return }
    statusBarController.environmentInstallStarted()
    let inst = EnvironmentInstaller(backend: backend)
    inst.onComplete = { [weak self] _ in
        self?.statusBarController.environmentInstallFinished()
        self?.backgroundInstaller = nil
    }
    inst.install()
    backgroundInstaller = inst
}
```

- [ ] Update `bootstrapEnvironmentIfNeeded()` as above

### Step 6.4: Build to catch any remaining compile errors

```bash
swift build
```

Fix any remaining call sites that reference the old `findMLXServer()` or old static `EnvironmentInstaller.pythonPath`.

- [ ] Build succeeds with no errors

### Step 6.5: Run full suite

```bash
swift test
```

- [ ] All tests pass

### Step 6.6: Commit

```bash
git add Sources/MLXManagerApp/AppDelegate.swift
git commit -m "refactor: update AppDelegate to use withResolvedPythonPath(), backend-aware scanner and bootstrapper"
```

- [ ] Commit

---

## Task 7: Settings UI — backend picker and conditional fields

**Files:**

- Modify: `Sources/MLXManagerApp/SettingsWindowController.swift`

This task is UI-only. No unit tests for AppKit layout — verify visually by running the app.

### Step 7.1: Add backend segmented control property

At the top of `SettingsWindowController` with the other field declarations, add:

```swift
private let detailBackend = NSSegmentedControl(
    labels: ["LM", "VLM"],
    trackingMode: .selectOne,
    target: nil,
    action: nil
)
```

- [ ] Add `detailBackend` property

### Step 7.2: Add VLM-only field properties

```swift
// mlx-vlm only fields
private let detailKvBits           = NSTextField()
private let detailKvGroupSize      = NSTextField()
private let detailMaxKvSize        = NSTextField()
private let detailQuantizedKvStart = NSTextField()
```

- [ ] Add VLM field properties

### Step 7.3: Add a Backend column to the preset list table

In `buildPresetsView()`, add a third table column after the model column:

```swift
let backendCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("listBackend"))
backendCol.title = "Backend"
backendCol.width = 55
backendCol.isEditable = false
presetListTable.addTableColumn(backendCol)
```

In `tableView(_:viewFor:row:)`, handle `"listBackend"`:
```swift
case "listBackend": return preset.serverType == .mlxLM ? "LM" : "VLM"
```

- [ ] Add backend column to table and handle it in the data source

### Step 7.4: Wire backend segmented control and VLM fields into the detail form

In `buildPresetsView()`, update `detailFields` to include the VLM rows:

```swift
// At the top of the grid, before Name:
// Backend row
let backendLabel = NSTextField(labelWithString: "Backend:")
backendLabel.alignment = .right
detailBackend.target = self
detailBackend.action = #selector(backendChanged)
grid.addRow(with: [backendLabel, detailBackend])

// After Extra Args and before Trust Remote Code, add the VLM fields:
let vlmFields: [(String, NSTextField)] = [
    ("KV Bits:",        detailKvBits),
    ("KV Group Size:",  detailKvGroupSize),
    ("Max KV Size:",    detailMaxKvSize),
    ("KV Start:",       detailQuantizedKvStart),
]
for (_, field) in vlmFields {
    field.isEditable = true
    field.target = self
    field.action = #selector(detailFieldChanged(_:))
}
for (label, field) in vlmFields {
    let lbl = NSTextField(labelWithString: label)
    lbl.alignment = .right
    grid.addRow(with: [lbl, field])
}
```

- [ ] Wire backend segmented control and VLM fields into the grid

### Step 7.5: Implement `backendChanged` and field visibility

```swift
@objc private func backendChanged() {
    let row = presetListTable.selectedRow
    guard row >= 0, row < draftPresets.count else { return }
    let backend: ServerType = detailBackend.selectedSegment == 0 ? .mlxLM : .mlxVLM
    // Rebuild preset with new backend
    let p = draftPresets[row]
    draftPresets[row] = ServerConfig(
        name: p.name, model: p.model, maxTokens: p.maxTokens,
        port: p.port, prefillStepSize: p.prefillStepSize,
        promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
        trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
        extraArgs: p.extraArgs, serverType: backend,
        kvBits: p.kvBits, kvGroupSize: p.kvGroupSize,
        maxKvSize: p.maxKvSize, quantizedKvStart: p.quantizedKvStart,
        pythonPath: p.pythonPath
    )
    updateFieldVisibility(for: backend)
    presetListTable.reloadData(
        forRowIndexes: IndexSet(integer: row),
        columnIndexes: IndexSet(integersIn: 0..<presetListTable.numberOfColumns)
    )
}

// Store label refs alongside each backend-specific field so we can hide both together.
// Add these as properties alongside the field declarations:
//   private let detailMaxTokensLabel    = NSTextField(labelWithString: "Context:")
//   private let detailCacheSizeLabel    = NSTextField(labelWithString: "Cache Size:")
//   private let detailCacheBytesLabel   = NSTextField(labelWithString: "Cache Bytes:")
//   private let detailEnableThinkingRow = NSView()  // wrapper (or use the checkbox directly)
//   private let detailKvBitsLabel       = NSTextField(labelWithString: "KV Bits:")
//   ... etc.
//
// Then in buildPresetsView(), use those label refs when adding rows to the grid,
// so you can hide both the label and the field as a pair.

private func updateFieldVisibility(for backend: ServerType) {
    let isLM = backend == .mlxLM
    // LM-only: hide field AND its matching label
    let lmPairs: [(NSView, NSView)] = [
        (detailMaxTokensLabel, detailMaxTokens),
        (detailCacheSizeLabel, detailCacheSize),
        (detailCacheBytesLabel, detailCacheBytes),
        (NSView(), detailEnableThinking),   // replace NSView() with the actual label ref
    ]
    for (label, field) in lmPairs {
        label.isHidden = !isLM
        field.isHidden = !isLM
    }
    // VLM-only: hide field AND its matching label
    let vlmPairs: [(NSView, NSView)] = [
        (detailKvBitsLabel, detailKvBits),
        (detailKvGroupSizeLabel, detailKvGroupSize),
        (detailMaxKvSizeLabel, detailMaxKvSize),
        (detailQuantizedKvStartLabel, detailQuantizedKvStart),
    ]
    for (label, field) in vlmPairs {
        label.isHidden = isLM
        field.isHidden = isLM
    }
}
```

Note: NSGridView rows cannot be hidden directly in all macOS versions. Use `isHidden` on both the label and field views for each row, or wrap each backend-specific group in an `NSStackView` that can be hidden as a unit. Choose whichever approach is cleaner given the existing grid setup.

- [ ] Implement `backendChanged` and `updateFieldVisibility`

### Step 7.6: Update `populateDetail` to populate VLM fields and control backend segment

In `populateDetail(row:)`, add:

```swift
detailBackend.selectedSegment = p.serverType == .mlxLM ? 0 : 1
detailKvBits.stringValue           = String(p.kvBits)
detailKvGroupSize.stringValue      = String(p.kvGroupSize)
detailMaxKvSize.stringValue        = String(p.maxKvSize)
detailQuantizedKvStart.stringValue = String(p.quantizedKvStart)
updateFieldVisibility(for: p.serverType)
```

- [ ] Update `populateDetail` for VLM fields

### Step 7.7: Update `applyDetail` to read VLM fields

In `applyDetail()`, add VLM fields to the `ServerConfig` reconstruction:

```swift
draftPresets[row] = ServerConfig(
    name:             ...,  // existing fields
    ...
    serverType:       detailBackend.selectedSegment == 0 ? .mlxLM : .mlxVLM,
    kvBits:           Int(detailKvBits.stringValue) ?? p.kvBits,
    kvGroupSize:      Int(detailKvGroupSize.stringValue) ?? p.kvGroupSize,
    maxKvSize:        Int(detailMaxKvSize.stringValue) ?? p.maxKvSize,
    quantizedKvStart: Int(detailQuantizedKvStart.stringValue) ?? p.quantizedKvStart,
    pythonPath:       detailPythonPath.stringValue
)
```

- [ ] Update `applyDetail` to include VLM fields

### Step 7.8: Update environment install button to use backend from selected preset

In `installEnvironment()`:

```swift
@objc private func installEnvironment() {
    installerOutput.string = ""
    let backend = draftPresets[safe: presetListTable.selectedRow]?.serverType ?? .mlxLM
    let label = backend == .mlxLM ? "mlx-lm" : "mlx-vlm"
    // Update button label (store a reference to installButton as a property if needed)
    let inst = EnvironmentInstaller(backend: backend)
    ...
}
```

Also update the install button label dynamically in `populateDetail`:
```swift
installButton.title = "Install / Reinstall \(p.serverType == .mlxLM ? "mlx-lm" : "mlx-vlm")"
```

(Store `installButton` as a `private let` property instead of a local variable to allow this.)

- [ ] Update install button to use selected preset's backend

### Step 7.9: Build and visually verify

```bash
swift build
```

Run the app and verify:
- Preset list shows Backend column
- Selecting an LM preset shows LM fields, hides VLM fields
- Selecting a VLM preset shows VLM fields, hides LM fields
- Switching backend segment updates the field set immediately
- Install button label changes per backend

- [ ] Build succeeds, verify UI behaviour manually

### Step 7.10: Commit

```bash
git add Sources/MLXManagerApp/SettingsWindowController.swift
git commit -m "feat: add backend picker and conditional field visibility to Settings UI"
```

- [ ] Commit

---

## Task 8: Add VLM presets to bundled `presets.yaml`

**Files:**

- Modify: `Sources/MLXManagerApp/presets.yaml`

### Step 8.1: Add VLM example presets

Append to `Sources/MLXManagerApp/presets.yaml`:

```yaml
- name: VLM Qwen2.5-VL 7B 4bit
  serverType: mlxVLM
  model: mlx-community/Qwen2.5-VL-7B-Instruct-4bit
  maxTokens: 0
  port: 8082
  pythonPath: ~/.mlx-manager/venv-vlm/bin/python
  prefillStepSize: 512
  trustRemoteCode: false

- name: VLM Qwen2.5-VL 3B 4bit
  serverType: mlxVLM
  model: mlx-community/Qwen2.5-VL-3B-Instruct-4bit
  maxTokens: 0
  port: 8082
  pythonPath: ~/.mlx-manager/venv-vlm/bin/python
  prefillStepSize: 512
  trustRemoteCode: false
```

> **Note:** `maxTokens` is a required field in `ConfigLoader` — it throws `ConfigError.missingField("maxTokens")` if absent. VLM presets don't use it, but it must be present in the YAML. Set it to `0`.

- [ ] Append VLM presets to `Sources/MLXManagerApp/presets.yaml`

### Step 8.2: Verify `ConfigLoader` decodes them correctly

Run the existing `ConfigLoaderTests` — they decode the bundled YAML and check field values. Add a quick check that VLM presets decode with the right `serverType`:

```bash
swift test --filter ConfigLoaderTests
```

If existing tests only check lm presets, add one test that verifies a VLM preset decodes `serverType == .mlxVLM`. Add it to `Tests/MLXManagerTests/ConfigLoaderTests.swift` if missing.

- [ ] Run ConfigLoader tests and verify VLM preset decoding

### Step 8.3: Commit

```bash
git add Sources/MLXManagerApp/presets.yaml
git commit -m "feat: add Qwen2.5-VL example VLM presets to bundled presets.yaml"
```

- [ ] Commit

---

## Task 9: Update `docs/SPEC.md`

**Files:**

- Modify: `docs/SPEC.md`

### Step 9.1: Update SPEC.md

In `docs/SPEC.md`, update the following sections to reflect dual-backend reality:

- **Server Control** section: note both `mlx_lm.server` and `mlx_vlm.server` are supported; mention `ServerArgBuilder`
- **PID Recovery** section: update "Detect running `mlx_lm.server`" to "Detect running server (backend-aware via `findServer(backend:)`)"
- **Config Presets** section: note `serverType` field (default `mlxLM`), separate venvs
- **Environment Bootstrap** section: note separate venvs per backend, update step 3 to show both packages

- [ ] Update `docs/SPEC.md` to reflect dual-backend reality

### Step 9.2: Commit

```bash
git add docs/SPEC.md
git commit -m "docs: update SPEC.md for dual-backend support"
```

- [ ] Commit

---

## Done

All tasks complete. The app now supports both `mlx-lm` and `mlx-vlm` as first-class backends with:
- Per-backend venvs and correct arg assembly
- Backend-aware process recovery on launch
- Settings UI with dynamic field visibility
- Bundled VLM example presets
