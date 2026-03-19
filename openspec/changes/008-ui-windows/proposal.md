# Proposal: 008-ui-windows

## Problem

The app controls the server well, but has four gaps once it's running:

1. **No visual request progress** — the status bar icon shows a glyph progress bar, but
   when you glance at the bar while waiting for a response, you can't read an actual
   percentage or see how fast tokens are accumulating. There's no live animated indicator
   in the menu itself.

2. **No settings UI** — `presets.yaml` is bundled read-only. There is no way to change
   pythonPath, model, context size, or args without editing a file by hand. Also, the app
   currently assumes the Python/mlx-lm environment already exists at a hardcoded path with
   no setup step.

3. **No RAM graph** — Unified memory pressure is the main constraint on an Apple Silicon
   machine running a large model. There is currently no way to monitor memory usage over
   time without opening Activity Monitor.

4. **No log viewer** — log output is parsed silently. Debugging requires a terminal.

5. **No request history** — no way to see how long past requests took or spot trends.

## Proposed Solution

### 1. Live Request Progress in the Status Bar

The status bar button shows a richer animated indicator during processing:

- **Default mode**: `▓▓▓▓░░░░░░ 41%` — filled/empty block bar + percentage, updated on
  every progress line (already partially there, needs the percentage text added)
- **Optional pie mode** (toggleable in Settings): a filled circle that grows, rendered as
  a Unicode pie glyph sequence (○ → ◔ → ◑ → ◕ → ●)

The menu also gets a non-clickable **status line item** directly below the icon:
- Offline: `Server: Offline`
- Idle: `Server: Idle  ●`
- Processing: `27,611 / 41,061 tokens  (67%)`

This gives a readable at-a-glance status without opening the menu.

### 2. Settings Window

A panel accessible via "Settings…" in the menu. Two tabs:

**Presets tab** — table of presets, each row editable:
- Name (text field)
- Python path (text field + "Browse…" button → open panel)
- Model (text field — model ID string, no dynamic fetch)
- Context size (integer field → `--max-seq-len`)
- Extra args (text field — appended verbatim)
- Add / Remove preset buttons

Changes saved to `~/.config/mlx-manager/presets.yaml` on "Save". App re-reads presets
after save and rebuilds the menu. Falls back to bundled `presets.yaml` when the user file
is absent (first launch).

**General tab**:
- Progress indicator style: Block bar (default) | Pie glyphs
- RAM graph: Enabled / Disabled (default: Disabled)
- RAM graph poll interval: 2s / 5s / 10s (default: 5s)

Settings persisted to `~/.config/mlx-manager/settings.json`.

### 3. RAM Graph Window

A resizable NSWindow opened via "RAM Graph" menu item (only visible when RAM graph is
enabled in Settings). Contains a scrolling line chart of the server process's RSS (resident
set size) sampled at the configured interval using `proc_pidinfo` / `task_info` via Swift's
`Foundation.Process` or a direct `sysctl` call — no Python, no psutil.

Y-axis: GB. X-axis: time (last N minutes, configurable 5/15/30). A horizontal dashed line
marks the machine's total RAM.

### 4. Log Viewer Window

A resizable NSWindow opened via "Show Log" menu item. Contains a scrolling `NSTextView`
with raw log lines appended in real-time. Auto-scrolls to bottom unless user has scrolled
up. "Clear" button. Lines are colour-coded:
- Progress lines → default text colour
- KV Caches lines → blue tint
- HTTP completion lines → green tint
- WARNING / ERROR lines → orange/red tint

Buffer capped at 10,000 lines. Cleared when server restarts.

### 5. Request History Graph

A resizable NSWindow opened via "Request History" menu item. A bar chart where each
completed request is one bar:
- Bar height = tokens (from final `KV Caches:` line)
- Bar colour intensity = duration (darker = longer)
- Hover tooltip = start time, duration (seconds), token count

In-memory only, cleared on server restart. History capped at 500 requests.

## Python Environment Self-Containment

Currently the app hard-codes `pythonPath` per preset (pointing at a local venv). A new
user would need to manually create a venv, install `mlx-lm`, and update the path.

The Settings window MUST include a **"Set Up Environment"** section:
- Displays the currently configured default python path
- A "Set Up / Reinstall" button that, when clicked:
  1. Creates `~/.mlx-manager/venv/` if absent
  2. Runs `python3 -m venv ~/.mlx-manager/venv`
  3. Runs `~/.mlx-manager/venv/bin/pip install mlx-lm`
  4. On success, offers to update all preset pythonPaths to
     `~/.mlx-manager/venv/bin/python`
- Progress shown inline (streaming pip output into a small text area in the panel)
- This is the only place environment installation happens — no silent auto-install

The bundled `presets.yaml` ships with `pythonPath: ~/.mlx-manager/venv/bin/python`
as the default, so the app works out of the box if the user runs "Set Up Environment" once.

## What Changes

### New value types (MLXManager layer)

| Type | Purpose |
|------|---------|
| `RequestRecord` | `startedAt`, `completedAt`, `tokens: Int` — one completed request |
| `RAMSample` | `timestamp: Date`, `gb: Double` — one memory reading |
| `AppSettings` | `progressStyle`, `ramGraphEnabled`, `ramPollInterval` |
| `UserPresetStore` | load/save presets from `~/.config/mlx-manager/presets.yaml` |

### New UI components (App layer)

| Component | Purpose |
|-----------|---------|
| `LogWindowController` | NSWindow + NSTextView, live log lines |
| `HistoryWindowController` | NSWindow + bar chart NSView |
| `RAMGraphWindowController` | NSWindow + line chart NSView |
| `SettingsWindowController` | NSWindow + NSTabView, two tabs |
| `EnvironmentInstaller` | Runs venv + pip, streams output |
| `RAMPoller` | Timer-based process RSS sampler |

### Changes to existing components

- `ServerState` — track request `startedAt`; emit `RequestRecord` on completion
- `StatusBarController` — add status text item; add "Show Log", "Request History",
  "RAM Graph", "Settings…" menu items; support pie/bar progress style
- `AppDelegate` — wire all new windows; own log buffer, request history, RAM samples

## Out of Scope

- Persisting request history or RAM samples across restarts
- Filtering/searching the log viewer
- Pulling model lists dynamically from HuggingFace
- Multiple concurrent server instances
- Auto-updating mlx-lm
