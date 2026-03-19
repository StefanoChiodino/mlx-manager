# MLX Manager - Open Spec v1.0

## Overview
A macOS menu bar application that manages MLX LLM server with one-click start/stop and live progress monitoring.

## Problem Statement
Current MLX server setup requires manual terminal commands and monitoring. Users want:
- One-click start/stop from menu bar
- Live progress tracking during processing
- Simple status display without complex monitoring tools

## Core Features

### 1. Menu Bar Interface
- **Single icon** in macOS status bar
- **Dropdown menu** with:
  - Current server status indicator (Running/Stopped)
  - One-click **Start** / **Stop** / **Restart** buttons
  - Quick config selector (4-bit vs 8-bit, different context sizes)
  - Current progress percentage display

### 2. Progress Monitoring (Critical Fix)

**Problem Discovered**: MLX server logs don't show "100%" completion - processing just finishes silently without a completion marker.

**Evidence from logs**:
```
2026-03-18 23:39:48,761 - INFO - Prompt processing progress: 8192/8333
2026-03-18 23:39:49,189 - INFO - Prompt processing progress: 8328/8333
[no further progress lines - job completes silently]
```

**Solution**: Parse `Prompt processing progress: X/Y` from server logs and calculate percentage:
```python
match = re.match(r'Prompt processing progress:\s*(\d+)/(\d+)', line)
if match:
    current, total = int(match.group(1)), int(match.group(2))
    progress = (current / total) * 100
    # When X == Y or no new progress lines appear for N seconds, mark complete
```

**Completion Detection**:
- When `current == total` (e.g., `8328/8333` completes)
- When next log shows different endpoint (new request started)
- When `KV Caches` appears with no subsequent progress lines

**Display**: Show `Processing: 8328/8333 (99%)` or `Complete`

### 3. Live Metrics (Display in Menu)

**GPU Memory**: Extract from `KV Caches: N seq, X.XX GB`
```python
match = re.match(r'KV Caches:\s*\d+\s+seq,\s*([\d.]+)\s+GB', line)
gpu_gb = float(match.group(1)) if match else 0
```

**Token Count**: Extract from `latest user cache Y tokens`

**Progress**: Calculated from progress logs (see above)

**Simple Status**: `Running`, `Processing: X%`, `Complete`

### 4. Config Presets (From Current MLX Repo)

Based on benchmark findings:

| Config | Model | Context | Memory | Use Case |
|--------|-------|---------|--------|----------|
| 4-bit 40k | Qwen3.5-35B-A3B-4bit | 40,960 | ~25-30GB | Memory efficient |
| 4-bit 80k | Qwen3.5-35B-A3B-4bit | 81,920 | ~30-35GB | Balanced |
| 8-bit 40k | Qwen3.5-35B-A3B-8bit | 40,960 | ~35-40GB | Max quality |
| 8-bit 80k | Qwen3.5-35B-A3B-8bit | 81,920 | ~40-45GB | Large context |

### 5. Settings Panel (Future)
- Add custom models
- Adjust context sizes
- Configure advanced flags

## Technical Constraints

### Debug Mode: NOT Recommended
**Issue**: Debug mode generates **100x more log lines**, making parsing confusing and resource-intensive.

**Decision**: Use **INFO level only**, parse `Prompt processing progress:` and `KV Caches:` lines.

### Log Parsing Strategy
```
INFO lines to parse:
- "Prompt processing progress: X/Y" → progress percentage
- "KV Caches: N seq, X.XX GB, latest user cache Y tokens" → GPU memory, tokens

Ignore:
- HTTP request lines ("POST /v1/chat/completions")
- Fetching progress (model download)
- Warnings and resource_tracker messages
```

## Technical Approach

### Platform
- **macOS only** (Apple Silicon)
- **Swift** for menu bar app (native, simple)
- Or **Python + PyObjC** (if you prefer Python stack)

### Architecture
```
mlx-manager/
├── MLXManager.app (macOS app)
│   └── main.swift / main.py
├── server-launcher.py (helper script to start/stop server)
├── log-parser.py (extracts progress from logs)
└── configs/ (predefined configs)
```

### API (Optional, for future)
```
GET  /status        - Current server status
POST /start         - Start MLX server with config
POST /stop          - Stop server
POST /restart       - Restart server
GET  /progress      - Current progress percentage
GET  /metrics       - GPU memory, token count
```

## MVP Scope

### Phase 1 (MVP)
1. macOS menu bar app (Swift or Python)
2. Start/stop/restart MLX server with config selection
3. Parse INFO logs for progress percentage
4. Display GPU memory usage
5. Config presets from current mlx repo

### Phase 2 (Nice-to-Have)
- Settings panel UI
- Custom config builder
- Multiple server instances (different ports)
- Session history export (optional)

## File Structure (MVP)

```
mlx-manager/
├── OpenSpec.md          # This spec
├── README.md            # Usage instructions
├── src/
│   ├── main.swift       # Menu bar app entry point (Swift)
│   │   # OR
│   ├── main.py          # Menu bar app entry point (Python)
│   ├── server.py        # MLX server launcher/wrapper
│   ├── log_parser.py    # Parse progress from logs
│   └── configs/
│       └── presets.yaml # Config presets
└── Logs/                # Server logs (optional, configurable)
```

## Configuration Schema

```yaml
# presets.yaml
configs:
  - name: "4-bit, 40k"
    model: "mlx-community/Qwen3.5-35B-A3B-4bit"
    max_tokens: 40960
    temp: 0.7
    args: ["--trust-remote-code", "--chat-template-args '{\"enable_thinking\":false}'"]
    
  - name: "4-bit, 80k"
    model: "mlx-community/Qwen3.5-35B-A3B-4bit"
    max_tokens: 81920
    temp: 0.7
    args: ["--trust-remote-code"]
    
  - name: "8-bit, 40k"
    model: "mlx-community/Qwen3.5-35B-A3B-8bit"
    max_tokens: 40960
    temp: 0.7
    args: ["--trust-remote-code"]
    
  - name: "8-bit, 80k"
    model: "mlx-community/Qwen3.5-35B-A3B-8bit"
    max_tokens: 81920
    temp: 0.7
    args: ["--trust-remote-code"]
```

## Progress Parsing Implementation

```python
# log_parser.py
import re
from dataclasses import dataclass

@dataclass
class Progress:
    current: int
    total: int
    percentage: float
    gpu_gb: float
    tokens: int
    is_complete: bool

def parse_log_line(line: str) -> Progress | None:
    # Progress line: "Prompt processing progress: 4096/8333"
    progress_match = re.match(r'Prompt processing progress:\s*(\d+)/(\d+)', line)
    if progress_match:
        current, total = int(progress_match.group(1)), int(progress_match.group(2))
        return Progress(
            current=current,
            total=total,
            percentage=(current / total) * 100,
            gpu_gb=0,
            tokens=0,
            is_complete=current == total
        )
    
    # KV Caches line: "KV Caches: 4 seq, 1.94 GB, latest user cache 25724 tokens"
    kv_match = re.match(r'KV Caches:\s*\d+\s+seq,\s*([\d.]+)\s+GB.*?(\d+)\s+tokens', line)
    if kv_match:
        gpu_gb = float(kv_match.group(1))
        tokens = int(kv_match.group(2))
        return Progress(
            current=0, total=0, percentage=0,
            gpu_gb=gpu_gb, tokens=tokens, is_complete=False
        )
    
    return None
```

## Open Questions

1. **Tech stack**: Swift (native macOS) or Python (PyObjC)?
2. **Progress display**: Show in menu bar icon (small text) or just dropdown?
3. **Server auto-start**: Should it auto-start on login?
4. **Log location**: Where should logs be stored? (current: `mlx/Logs/server.log`)
5. **Update interval**: How often to poll logs? (1s, 500ms, event-driven?)

## Next Steps

1. Confirm tech stack (Swift vs Python)
2. Define MVP scope (Phase 1 features)
3. Create initial repo structure
4. Implement log parser with test cases
5. Build menu bar interface

---

**Status**: Spec complete, awaiting implementation decision.
