# Dual-Backend Support: mlx-lm + mlx-vlm

**Date:** 2026-03-22
**Status:** Approved

## Overview

Add support for `mlx-vlm` as a second server backend alongside the existing `mlx-lm`. Users can configure presets against either backend. One server runs at a time. Each backend gets its own Python venv to avoid dependency conflicts.

---

## Constraints & Decisions

- **One server at a time.** Multi-server orchestration is out of scope. Each preset already has its own port, so future multi-server support is not precluded.
- **Separate venvs** per backend (`~/.mlx-manager/venv` for mlx-lm, `~/.mlx-manager/venv-vlm` for mlx-vlm).
- **Dynamic UI** — the settings detail form shows/hides fields based on the selected backend.
- **Backwards compatible** — existing YAML presets without a `backend:` key decode as `mlx_lm`.
- **Process scanning** is backend-aware: the scanner looks for the module name matching the active preset's backend.

---

## Existing State

`ServerType` and a partial `serverType` field on `ServerConfig` already exist in the codebase. The design below builds on this foundation rather than replacing it with a new `Backend` enum. Specifically:

- `ServerType` (raw values `"mlxLM"` / `"mlxVLM"`) already has `serverEntryName` and `serverModule` computed properties — these are correct and are kept.
- `ServerConfig` already has `serverType: ServerType` (default `.mlxLM`).
- `EnvironmentBootstrapper` currently installs only `mlx-lm` into a single venv (`~/.mlx-manager/venv`). It needs to be made backend-aware.
- `ServerManager.start()` still hardcodes `mlx_lm.server` — it does not yet use `serverType`.

---

## Data Model

### `ServerType` (existing, kept as-is)

```swift
public enum ServerType: String, Codable, CaseIterable {
    case mlxLM  = "mlxLM"
    case mlxVLM = "mlxVLM"
}
```

The YAML key `backend:` maps to `serverType` via a custom `CodingKeys` mapping, or the YAML uses `serverType` directly. Either approach is fine — implementer's choice — but must be documented in a code comment. Existing YAML without this key decodes as `.mlxLM`.

### `ServerConfig` additions

The existing fields are kept. New fields added:

**mlx-vlm only** (new):
| Field | Type | Default |
|---|---|---|
| `kvBits` | Int | 0 (omit flag when 0) |
| `kvGroupSize` | Int | 64 |
| `maxKvSize` | Int | 0 (omit flag when 0) |
| `quantizedKvStart` | Int | 0 |

The existing mlx-lm fields (`maxTokens`, `promptCacheSize`, `promptCacheBytes`, `enableThinking`) are retained on the struct with their current defaults — they are simply not passed to the server when `serverType == .mlxVLM`.

### `ServerConfig.withResolvedPythonPath()` helper

`AppDelegate.resolvedPythonPath(_:)` currently reconstructs `ServerConfig` via the memberwise init, passing only a subset of fields. Adding new fields would silently drop them. Replace the private `AppDelegate` helper with a method on `ServerConfig` itself:

```swift
public func withResolvedPythonPath() -> ServerConfig
```

This copies all fields, replacing only `pythonPath` with the tilde-expanded version. All call sites in `AppDelegate` update to use this method.

---

## Argument Building

Extract argument assembly from `ServerManager.start()` into a `ServerArgBuilder` protocol:

```swift
public protocol ServerArgBuilder {
    func arguments(for config: ServerConfig) -> [String]
}
```

**`MLXLmArgBuilder`** emits:
```
-m mlx_lm.server
--model <model>
--max-tokens <maxTokens>
--port <port>
--prefill-step-size <prefillStepSize>
--prompt-cache-size <promptCacheSize>
--prompt-cache-bytes <promptCacheBytes>
[--trust-remote-code]            (only if trustRemoteCode == true)
--chat-template-args {"enable_thinking":<true|false>}   (always emitted; intentional)
[extraArgs...]
```

Note: `--chat-template-args` with `enable_thinking: false` is always emitted for mlx-lm presets. This matches existing behaviour and is intentional — mlx-lm accepts this flag for all models.

**`MLXVlmArgBuilder`** emits:
```
-m mlx_vlm.server
--model <model>
--port <port>
--prefill-step-size <prefillStepSize>
[--trust-remote-code]            (only if trustRemoteCode == true)
[--kv-bits <kvBits>]             (only if kvBits > 0)
[--kv-group-size <kvGroupSize>]  (only if kvBits > 0; meaningless otherwise)
[--max-kv-size <maxKvSize>]      (only if maxKvSize > 0)
[--quantized-kv-start <n>]       (only if kvBits > 0)
[extraArgs...]
```

`ServerManager.start()` selects the builder using `config.serverType.serverEntryName` (already exists) and calls the builder:

```swift
let builder: ServerArgBuilder = config.serverType == .mlxLM
    ? MLXLmArgBuilder() : MLXVlmArgBuilder()
let arguments = builder.arguments(for: config)
```

Both builders are independently unit-testable. `ServerManager` gains no new logic.

---

## Process Scanner

`findMLXServer()` is renamed to `findServer(backend:)` (parameter label uses `ServerType`):

```swift
public func findServer(backend: ServerType) -> DiscoveredProcess?
```

All existing tests calling `findMLXServer()` are updated to call `findServer(backend: .mlxLM)`.

Detection patterns per backend:

| Backend | Patterns |
|---|---|
| `.mlxLM` | `-m mlx_lm.server`, bare `mlx_lm.server` element, `mlx_lm/server.py` suffix, `/mlx_lm.server` suffix |
| `.mlxVLM` | `-m mlx_vlm.server`, bare `mlx_vlm.server` element, `mlx_vlm/server.py` suffix, `/mlx_vlm.server` suffix |

Cross-contamination is explicit: `findServer(backend: .mlxLM)` must return `nil` when only an `mlx_vlm.server` process is running, and vice versa.

Port extraction (`--port` argument) is unchanged.

Call sites in `AppDelegate` pass the active preset's `serverType` when scanning on launch.

---

## Environment Installer

Two separate venvs:

| Backend | Venv path | Package installed |
|---|---|---|
| `.mlxLM` | `~/.mlx-manager/venv` | `mlx-lm` |
| `.mlxVLM` | `~/.mlx-manager/venv-vlm` | `mlx-vlm` |

`EnvironmentBootstrapper` gains a `backend: ServerType` parameter (defaulting to `.mlxLM` for backwards compatibility). The `venvPath` and `pythonPath` static properties become static methods:

```swift
static func venvPath(for backend: ServerType) -> String
static func pythonPath(for backend: ServerType) -> String
```

Install steps (same structure, different paths/packages):
1. `uv venv <venvPath> --python 3.12`
2. `uv pip install <package> --python <pythonPath>`

Where `<package>` is `mlx-lm` for `.mlxLM` and `mlx-vlm` for `.mlxVLM`.

---

## Settings UI

### Preset list table

Gains a small **Backend** column ("LM" / "VLM") so the user can identify preset type at a glance.

### Detail form

A **Backend** segmented control appears at the top of the detail form. Changing it immediately shows/hides the relevant fields and updates the preset's `serverType`.

**Always visible:**
- Name, Python Path, Model, Port, Prefill Step Size, Trust Remote Code, Extra Args

**Visible for mlx-lm only** (hidden when backend = `.mlxVLM`):
- Context (maxTokens), Cache Size, Cache Bytes, Enable Thinking

**Visible for mlx-vlm only** (hidden when backend = `.mlxLM`):
- KV Bits, KV Group Size, Max KV Size, Quantized KV Start

### Environment box

The install button label updates to match the selected preset's backend:
- "Install / Reinstall mlx-lm"
- "Install / Reinstall mlx-vlm"

Triggers `EnvironmentBootstrapper(backend: preset.serverType)`.

---

## Bundled Presets (presets.yaml)

Existing 4 presets are unchanged — they decode as `serverType: mlxLM` by default.

New mlx-vlm example presets added:

```yaml
- name: VLM Qwen2.5-VL 7B 4bit
  serverType: mlxVLM
  model: mlx-community/Qwen2.5-VL-7B-Instruct-4bit
  port: 8082
  pythonPath: ~/.mlx-manager/venv-vlm/bin/python
  prefillStepSize: 512
  trustRemoteCode: false
```

---

## Files Touched

| File | Change |
|---|---|
| `Sources/MLXManager/ServerConfig.swift` | Add vlm-specific fields; add `withResolvedPythonPath()` method |
| `Sources/MLXManager/ServerArgBuilder.swift` | New — protocol + `MLXLmArgBuilder` + `MLXVlmArgBuilder` |
| `Sources/MLXManager/ServerManager.swift` | Use builder; remove hardcoded `mlx_lm.server` args |
| `Sources/MLXManager/ProcessScanner.swift` | Rename to `findServer(backend:)`; dual detection patterns |
| `Sources/MLXManager/EnvironmentBootstrapper.swift` | Add `backend` param; dual venv paths/packages |
| `Sources/MLXManagerApp/AppDelegate.swift` | Use `withResolvedPythonPath()`; pass `serverType` to scanner and bootstrapper |
| `Sources/MLXManagerApp/SettingsWindowController.swift` | Backend segmented control; show/hide fields; backend column in table |
| `Sources/MLXManagerApp/presets.yaml` | Add vlm example presets |
| `Tests/MLXManagerTests/ServerManagerTests.swift` | Tests for both arg builders |
| `Tests/MLXManagerTests/ProcessScannerTests.swift` | Migrate `findMLXServer()` → `findServer(backend: .mlxLM)`; add vlm + cross-contamination tests |
| `Tests/MLXManagerTests/ServerConfigTests.swift` | Round-trip tests for new vlm fields; `withResolvedPythonPath()` tests |
| `Tests/MLXManagerTests/EnvironmentBootstrapperTests.swift` | Tests for backend-aware venv paths |
| `docs/SPEC.md` | Update to reflect dual-backend |

---

## Testing

Every new unit of behaviour is driven by a failing test first (red-green-refactor).

Key test cases:

**Arg builders:**

- `MLXLmArgBuilder` emits all expected flags including `--chat-template-args`
- `MLXLmArgBuilder` omits `--trust-remote-code` when `trustRemoteCode == false`
- `MLXVlmArgBuilder` emits correct flags for all-defaults config
- `MLXVlmArgBuilder` omits `--kv-bits`, `--kv-group-size`, `--quantized-kv-start` when `kvBits == 0`
- `MLXVlmArgBuilder` emits `--kv-bits`, `--kv-group-size`, `--quantized-kv-start` when `kvBits > 0`
- `MLXVlmArgBuilder` omits `--max-kv-size` when `maxKvSize == 0`
- `MLXVlmArgBuilder` does not emit `--max-tokens`, `--prompt-cache-size`, `--chat-template-args`

**Process scanner:**

- `findServer(backend: .mlxLM)` matches all four lm patterns
- `findServer(backend: .mlxVLM)` matches all four vlm patterns
- `findServer(backend: .mlxLM)` returns `nil` when only an mlx_vlm process is running
- `findServer(backend: .mlxVLM)` returns `nil` when only an mlx_lm process is running

**ServerConfig:**

- YAML round-trip for both backends including all new vlm fields
- Existing preset YAML without `serverType` key decodes as `.mlxLM`
- `withResolvedPythonPath()` expands tilde, preserves all other fields

**EnvironmentBootstrapper:**

- `.mlxLM` uses `~/.mlx-manager/venv` and installs `mlx-lm`
- `.mlxVLM` uses `~/.mlx-manager/venv-vlm` and installs `mlx-vlm`
