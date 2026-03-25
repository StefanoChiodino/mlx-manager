# Core Spec — MLX Manager

## Log Reality (Evidence-Based)

> Observed from `~/repos/mlx/Logs/server.log` — these are the actual log patterns
> that drive all parsing and completion-detection logic.

**What the logs actually look like for one request cycle:**

```text
2026-03-18 23:33:34 - INFO - KV Caches: 0 seq, 0.00 GB, latest user cache 0 tokens
127.0.0.1 - - [18/Mar/2026 23:33:34] "POST /v1/chat/completions HTTP/1.1" 200 -
2026-03-18 23:33:38 - INFO - Prompt processing progress: 4096/41061
2026-03-18 23:33:41 - INFO - Prompt processing progress: 8192/41061
...
2026-03-18 23:34:18 - INFO - Prompt processing progress: 41056/41061   ← stops here, never hits 41061
2026-03-18 23:34:23 - INFO - KV Caches: 2 seq, 1.75 GB, ...            ← completion signal
127.0.0.1 - - [18/Mar/2026 23:34:23] "POST /v1/chat/completions HTTP/1.1" 200 -
```

**Key observations:**

1. Progress lines NEVER reach `current == total`. They always stop 1–5 tokens short.
2. The `KV Caches:` line immediately after the last progress line signals request completion.
3. The `POST ... 200` HTTP line is the canonical "request finished" marker.
4. Multiple requests can be interleaved — different `total` values appear in the same stream.
5. `KV Caches: 0 seq, 0.00 GB` appears at server start / after a cache flush.

**Completion detection strategy (in priority order):**

1. `POST /v1/chat/completions HTTP/1.1" 200` → current request is done
2. A new `KV Caches:` line appears after a progress sequence → previous request done
3. Timeout: no new progress line for N seconds → assume done (fallback only)

**`current == total` scenario:** Does not occur in practice.
Treat the last seen `current/total` as the final progress value; completion is signalled
externally by `KV Caches:` or `POST 200`, not by `current == total`.

---

## Requirements

### Menu Bar Icon States

The app displays a single custom-drawn `ArcProgressView` in the macOS status bar
button. The view has exactly three visual states driven by `StatusBarDisplayState`:

| State | Visual | Condition |
|-------|--------|-----------|
| `.offline` | Outline circle (tertiaryLabelColor) | Server process not running |
| `.idle` | Filled green circle (systemGreen) | Server running, no active request |
| `.processing(fraction)` | Clockwise-filling arc (controlAccentColor) + `N%` label | Progress lines being received |

The processing state renders a Core Graphics arc filling clockwise from 12 o'clock
proportional to `fraction = current / total`, with a percentage label to the right.
The view resizes itself via `intrinsicContentSize`.

#### Scenarios

- **Server offline** → hollow/offline icon
- **Server idle** (no progress since last completion) → green filled icon
- **Processing partial** (`4096/41061`) → `.processing(fraction: ≈0.0997)`, arc ~10%
- **Processing near complete** (`41056/41061`) → `.processing(fraction: >0.999)`, stays `.processing` until KV/POST signal
- **Completed via KV Caches** → transition processing → idle
- **Completed via POST 200** → transition processing → idle

---

### Log Parsing — Progress Line

Extract progress from: `Prompt processing progress: <current>/<total>`

Does NOT require `current == total` to indicate completion.

- Valid mid-request → `current = 4096, total = 41061, isComplete = false`
- Valid near-end → `current = 41056, total = 41061, isComplete = false`
- Non-progress line → `nil`

---

### Log Parsing — KV Caches Line

Extract from: `KV Caches: <n> seq, <gb> GB, latest user cache <tokens> tokens`

A `KV Caches:` line is also a completion signal.

- Valid → `gpuGB = 1.94, tokens = 25724, isCompletionSignal = true`
- Zero values (server start) → `gpuGB = 0.0, tokens = 0, isCompletionSignal = true`
- Non-KV line → `nil`

---

### Log Parsing — HTTP Completion Line

Recognise `POST /v1/chat/completions HTTP/1.1" 200` as a completion signal.

---

### Log Parsing — Ignored Lines

Return `nil` for: `Fetching`, `WARNING`, `resource_tracker:`, HTTP GETs, `Starting httpd at`

---

### Server Control

Both `mlx_lm.server` and `mlx_vlm.server` are supported as backends. `ServerArgBuilder` is used to assemble the correct command-line arguments for each backend based on the active preset's `serverType`.

- **Start**: Launch with the managed Python for the preset's backend, unless a global Python override is set in app settings
- **Stop**: Terminate running process, transition to offline
- **Restart**: Stop then start with same config
- **Process exit**: Clean up log tailing, update state to offline

---

### PID Recovery (via ProcessScanner)

Detect running server (backend-aware via `findServer(backend:)`) via `sysctl(KERN_PROCARGS2)`. Replaces PID file approach.

- App launch with server running → adopt process, show idle, start tailing
- App launch with no server → offline state
- Stop adopted process → SIGTERM, transition to offline
- Start guard → `ServerError.alreadyRunning` if process already running

---

### Config Presets

Load from bundled `presets.yaml` (4 presets). `pythonPath` is optional and defaults to the managed Python for the preset's backend.

User presets persisted to `~/.config/mlx-manager/presets.yaml`.
`UserPresetStore.load()` reads user file if present, otherwise falls back to bundled presets.

Each preset has a `serverType` field (default `mlxLM`). When `serverType` is `mlxVLM`, VLM-specific fields are available: `kvBits`, `kvGroupSize`, `maxKvSize`, `quantizedKvStart`.

---

### Log Tailing

Tail server log in real-time, parse via `LogParser`, emit `LogEvent` values.

- Start: seek to end, begin watching
- New lines: parse and emit events in order
- Partial lines: buffer until newline
- File truncation: reset to offset 0
- File rotation: detect inode change, reopen from offset 0, restart watcher
- Stop: release resources
- File not found: no-op

---

### Request Recording

`ServerState` tracks completed requests as `RequestRecord` (startedAt, completedAt, tokens, duration).
`AppDelegate` drains `serverState.completedRequest` and appends to history (capped at 500).

---

### App Settings

Persisted to `~/.config/mlx-manager/settings.json`.
Fields: `ramGraphEnabled` (default `false`), `ramPollInterval` (default `5`, allowed: 2/5/10), `logPath`, `pythonPathOverride` (optional global override).

---

### RAM Monitoring

Poll server process RSS via `proc_pidinfo` at configurable interval, emit `RAMSample` values.

---

### UI Windows

1. **Log Viewer** — scrolling text, colour-coded, clear button, 10k line cap
2. **Request History** — bar chart (height = tokens, opacity = duration)
3. **RAM Graph** — line chart of RAMSample values (only when `ramGraphEnabled`)
4. **Settings** — master-detail preset editor + general settings + environment install

---

### Menu Structure

- Preset header ("Start with:" when offline, "Switch to:" when running)
- Preset items (disabled + "(env missing)" when the resolved Python path for that preset is missing)
- Stop (only when running)
- Show Log, Request History
- RAM Graph (only when `ramGraphEnabled`)
- Settings…
- Quit

---

### Environment Bootstrap

Auto-detect missing Python environment on first launch. Uses `uv` for fast, version-pinned installs.

Separate venvs are maintained per backend:

- `~/.mlx-manager/venv` — for `mlx-lm` (used when `serverType` is `mlxLM`)
- `~/.mlx-manager/venv-vlm` — for `mlx-vlm` (used when `serverType` is `mlxVLM`)

Only the active preset's venv is bootstrapped on launch.

1. `uv venv ~/.mlx-manager/venv --python 3.12`
2. `uv pip install mlx-lm --python <venvPython>`
