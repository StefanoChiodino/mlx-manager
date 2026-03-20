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

**Critical**: The server never logs "100%" or "complete". Progress just stops when done.
Completion is inferred when `current == total` OR no new progress lines appear.

### Completion Detection Logic

- `current == total` in a progress line → complete
- A new `KV Caches:` line with no subsequent progress → request finished
- Next request starts → previous request was complete

### Log Lines to IGNORE

- `POST /v1/chat/completions` HTTP lines
- `Fetching:` lines (model download progress — different from inference progress)
- `WARNING` and `resource_tracker` lines
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
│   ├── StatusBarController.swift  # NSStatusItem management
│   ├── LogParser.swift         # Parse progress/KV lines from server logs
│   ├── ServerManager.swift     # Start/stop/restart MLX server process
│   ├── ProcessScanner.swift    # Detect any running mlx_lm.server via sysctl(KERN_PROCARGS2)
│   ├── ConfigLoader.swift      # Load YAML presets
│   └── Models/
│       ├── Progress.swift      # Progress value type
│       └── ServerConfig.swift  # Config preset value type
└── Tests/MLXManagerTests/
    ├── LogParserTests.swift
    ├── ServerManagerTests.swift
    └── ConfigLoaderTests.swift
```

## File Locations at Runtime

- Server log: `~/repos/mlx/Logs/server.log`
- Status output: `~/.mlx-status.json`
- Config presets: bundled in app at `Resources/presets.yaml`
- PID file: `~/.config/mlx-manager/server.pid`

## Coding Standards

- Value types (`struct`) preferred over classes
- No force-unwrap (`!`) in production code
- All public types documented with `///`
- Tests follow the pattern: `test_<subject>_<condition>_<expectedBehaviour>()`
