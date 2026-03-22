# MLX Manager — Project Context

## What This Is

A native macOS menu bar application (Apple Silicon only) that manages an MLX LLM server. Replaces manual terminal workflows with one-click start/stop, live progress monitoring, and config preset selection.

## Tech Stack

| Layer | Choice | Reason |
|-------|--------|--------|
| Language | Swift 5.9+ | Native macOS, best menu bar app support |
| UI | AppKit / NSStatusItem | Menu bar apps require AppKit, not SwiftUI |
| Testing | XCTest | Native Swift, required for Red-Green TDD |
| Build | Swift Package Manager | No Xcode project file needed for logic layer |
| Config | YAML (parsed in Swift) | Human-readable presets |

## Domain Knowledge

### MLX Server Log Format

The MLX server (`mlx_lm.server`) writes INFO-level logs. Two lines are parseable:

```
Prompt processing progress: 4096/8333
KV Caches: 4 seq, 1.94 GB, latest user cache 25724 tokens
```

**Critical**: The server never logs "100%" or "complete". Progress stops 1-5 tokens short of total.
Completion is inferred from external signals (`KV Caches:` line or `POST 200`), NOT from `current == total`.

### Completion Detection Logic (priority order)

1. `POST /v1/chat/completions HTTP/1.1" 200` → current request is done
2. A new `KV Caches:` line appears after a progress sequence → previous request done
3. Timeout: no new progress line for N seconds → assume done (fallback only)

### Log Lines to IGNORE

- `Fetching:` lines (model download progress — different from inference progress)
- `WARNING` and `resource_tracker` lines
- HTTP GET requests (HuggingFace model checks)
- `Starting httpd at` lines
- Debug-level output (not used — generates 100x volume)

### Config Presets

| Name | Model | Context | Notes |
|------|-------|---------|-------|
| 4-bit 40k | mlx-community/Qwen3.5-35B-A3B-4bit | 40,960 | Memory efficient |
| 4-bit 80k | mlx-community/Qwen3.5-35B-A3B-4bit | 81,920 | Balanced |
| 8-bit 40k | mlx-community/Qwen3.5-35B-A3B-8bit | 40,960 | Max quality |
| 8-bit 80k | mlx-community/Qwen3.5-35B-A3B-8bit | 81,920 | Large context |

All presets use `--trust-remote-code`. 4-bit 40k also uses `--chat-template-args '{"enable_thinking":false}'`.

### Existing Reference Implementation

`~/repos/mlx/` contains a working shell + Python implementation:
- `mlx_monitor.py` — daemon that tails `server.log`, writes `~/.mlx-status.json`
- `mlx-status.2s.sh` — SwiftBar plugin (refreshes every 2s)

This is reference material only. Do not copy from it; implement cleanly in Swift.

## Architecture

```
MLXManager.app
├── Sources/MLXManager/
│   ├── AppDelegate.swift       # NSApplicationDelegate, menu bar setup
│   ├── StatusBarController.swift  # NSStatusItem management + ArcProgressView
│   ├── LogParser.swift         # Parse progress/KV lines from server logs
│   ├── LogTailer.swift         # Real-time log tailing (handles file rotation via inode detection)
│   ├── ServerManager.swift     # Start/stop/restart MLX server process
│   ├── ProcessScanner.swift    # Detect any running mlx_lm.server via sysctl(KERN_PROCARGS2)
│   ├── AppSettings.swift       # User settings (ramGraphEnabled, ramPollInterval, logPath)
│   ├── ConfigLoader.swift      # Load YAML presets
│   └── Models/
│       ├── Progress.swift      # Progress value type
│       └── ServerConfig.swift  # Config preset value type
└── Tests/MLXManagerTests/
    ├── LogParserTests.swift
    ├── LogTailerTests.swift
    ├── ProcessScannerTests.swift
    ├── AppSettingsTests.swift
    ├── ServerManagerTests.swift
    └── ConfigLoaderTests.swift
```

## File Locations at Runtime

- Server log: `~/repos/mlx/Logs/server.log` (configurable via AppSettings.logPath)
- Status output: `~/.mlx-status.json`
- Config presets: bundled + user-editable at `~/.config/mlx-manager/presets.yaml`
- Settings: `~/.config/mlx-manager/settings.json`

## Coding Standards

- Value types (`struct`) preferred over classes
- No force-unwrap (`!`) in production code
- All public types documented with `///`
- Tests follow the pattern: `test_<subject>_<condition>_<expectedBehaviour>()`
