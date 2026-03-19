# Core Spec — MLX Manager

## Log Reality (Evidence-Based)

> Observed from `~/repos/mlx/Logs/server.log.2026-03-19` — these are the actual log patterns
> that drive all parsing and completion-detection logic in this spec.

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

**`current == total` scenario:** Remove this from tests. It does not occur in practice.
Treat the last seen `current/total` as the final progress value; completion is signalled
externally by `KV Caches:` or `POST 200`, not by `current == total`.

---

## Requirements

### Requirement: Menu Bar Icon States

The app MUST display a single custom-drawn `ArcProgressView` in the macOS status bar
button at all times while running. The view has exactly three visual states driven by
`StatusBarDisplayState`:

| State | Visual | Condition |
|-------|--------|-----------|
| `.offline` | Outline circle (tertiaryLabelColor) | Server process not running |
| `.idle` | Filled green circle (systemGreen) | Server running, no active request |
| `.processing(fraction)` | Clockwise-filling arc (controlAccentColor) + `N%` label | Progress lines being received |

The processing state MUST render a `Core Graphics` arc filling clockwise from 12 o'clock
proportional to `fraction = current / total`, with a percentage label to the right.
The view resizes itself via `intrinsicContentSize` so the status item width adapts.

`StatusBarViewProtocol.updateTitle(_:)` is replaced by `updateState(_: StatusBarDisplayState)`.

#### Scenario: Server offline

- GIVEN the MLX server process is not running
- WHEN the menu bar icon is rendered
- THEN it MUST display the hollow/offline icon

#### Scenario: Server idle

- GIVEN the server process is running
- AND no `Prompt processing progress:` lines have been seen since the last `POST 200` or `KV Caches:`
- WHEN the menu bar icon is rendered
- THEN it MUST display the green idle icon

#### Scenario: Server processing — partial progress

- GIVEN a `Prompt processing progress: 4096/41061` line was the most recent log event
- WHEN the status bar is updated
- THEN it MUST emit `.processing(fraction: ≈0.0997)`
- AND the arc MUST be filled approximately 10% clockwise from the top

#### Scenario: Server processing — near complete

- GIVEN the most recent progress line was `Prompt processing progress: 41056/41061`
- WHEN the status bar is updated
- THEN it MUST emit `.processing(fraction: >0.999)`
- AND the state MUST remain `.processing` until a `KV Caches:` or `POST 200` line is seen

#### Scenario: Request completed via KV Caches signal

- GIVEN progress was last seen at `41056/41061`
- WHEN a `KV Caches:` line is parsed
- THEN the state MUST transition from processing → idle

#### Scenario: Request completed via POST 200 signal

- GIVEN progress was last seen at any value
- WHEN a `POST /v1/chat/completions HTTP/1.1" 200` line is parsed
- THEN the state MUST transition from processing → idle

---

### Requirement: Log Parsing — Progress Line

The log parser MUST extract progress from lines matching:
`Prompt processing progress: <current>/<total>`

It MUST NOT require `current == total` to indicate completion.

#### Scenario: Valid progress line — mid-request

- GIVEN a log line `Prompt processing progress: 4096/41061`
- WHEN parsed
- THEN the result MUST have `current = 4096`, `total = 41061`, `percentage ≈ 9.97`
- AND `isComplete` MUST be `false`

#### Scenario: Valid progress line — near end (realistic maximum)

- GIVEN a log line `Prompt processing progress: 41056/41061`
- WHEN parsed
- THEN the result MUST have `current = 41056`, `total = 41061`, `percentage ≈ 99.99`
- AND `isComplete` MUST be `false` — completion is NOT inferred from progress alone

#### Scenario: Non-progress line

- GIVEN a log line `KV Caches: 4 seq, 1.94 GB, latest user cache 25724 tokens`
- WHEN parsed for a progress event
- THEN the result MUST be `nil`

---

### Requirement: Log Parsing — KV Caches Line

The log parser MUST extract GPU memory and token count from lines matching:
`KV Caches: <n> seq, <gb> GB, latest user cache <tokens> tokens`

A `KV Caches:` line is ALSO a completion signal and MUST be returned as such.

#### Scenario: Valid KV Caches line

- GIVEN a log line `KV Caches: 4 seq, 1.94 GB, latest user cache 25724 tokens`
- WHEN parsed
- THEN the result MUST have `gpuGB = 1.94`, `tokens = 25724`, `isCompletionSignal = true`

#### Scenario: KV Caches with zero values (server start)

- GIVEN a log line `KV Caches: 0 seq, 0.00 GB, latest user cache 0 tokens`
- WHEN parsed
- THEN the result MUST have `gpuGB = 0.0`, `tokens = 0`, `isCompletionSignal = true`

#### Scenario: Non-KV line

- GIVEN a log line `Prompt processing progress: 4096/8333`
- WHEN parsed for a KV event
- THEN the result MUST be `nil`

---

### Requirement: Log Parsing — HTTP Completion Line

The log parser MUST recognise `POST /v1/chat/completions HTTP/1.1" 200` as a completion signal.

#### Scenario: HTTP 200 completion line

- GIVEN a log line `127.0.0.1 - - [18/Mar/2026 23:34:23] "POST /v1/chat/completions HTTP/1.1" 200 -`
- WHEN parsed
- THEN the result MUST be a completion signal event

#### Scenario: Non-completion HTTP line

- GIVEN a log line that is not a POST to `/v1/chat/completions` with status 200
- WHEN parsed
- THEN the result MUST be `nil`

---

### Requirement: Log Parsing — Ignored Lines

The log parser MUST return `nil` for lines that carry no actionable information:

- `Fetching N files:` lines (model download progress bars)
- `WARNING` lines
- `resource_tracker:` lines
- `HTTP Request: GET https://...` lines (HuggingFace model check)
- `Starting httpd at` lines

---

### Requirement: Server Control — Start

The app MUST be able to start the MLX server with a selected config preset.

#### Scenario: Start with preset

- GIVEN a valid config preset is selected
- WHEN the user clicks Start
- THEN the server process MUST be launched using `config.pythonPath` as the command, with the correct CLI arguments for that preset

#### Scenario: Process exit notification

- GIVEN the server process is running
- WHEN the process terminates (crash, external kill, or natural exit)
- THEN `ServerManager.onExit` MUST be called
- AND the app MUST clean up log tailing and update state to offline

---

### Requirement: Server Control — Stop

The app MUST be able to stop a running MLX server process.

#### Scenario: Stop running server

- GIVEN the server process is running
- WHEN the user clicks Stop
- THEN the process MUST be terminated and state transitions to offline

---

### Requirement: Server Control — Restart

The app MUST support restarting the server (stop then start with the same config).

---

### Requirement: Server Control — PID Recovery

The app MUST persist the server process PID to `~/.config/mlx-manager/server.pid` and
recover running state across app restarts to prevent accidental double-launch.

#### Scenario: PID file written on start

- GIVEN a server is started successfully
- WHEN the process launches
- THEN the PID MUST be written to `~/.config/mlx-manager/server.pid` as a decimal string

#### Scenario: PID file deleted on stop

- GIVEN the server is running
- WHEN the user clicks Stop (or the process exits)
- THEN the PID file MUST be deleted

#### Scenario: Recovery — process alive

- GIVEN the PID file exists and the process is still alive (`kill(pid, 0) == 0`)
- WHEN the app launches
- THEN it MUST adopt the process, show idle state, and start log tailing

#### Scenario: Recovery — stale PID file

- GIVEN the PID file exists but the process is dead
- WHEN the app launches
- THEN it MUST delete the stale PID file and start in offline state

#### Scenario: Recovery — no PID file

- GIVEN no PID file exists
- WHEN the app launches
- THEN it MUST start in offline state (normal behaviour)

#### Scenario: Adopted process — stop

- GIVEN the app adopted an external process
- WHEN the user clicks Stop
- THEN the app MUST send SIGTERM to the adopted PID and transition to offline

#### Scenario: Adopted process — start guard

- GIVEN the app adopted an external process (or a launched process is running)
- WHEN the user clicks Start
- THEN it MUST throw `ServerError.alreadyRunning`

---

### Requirement: Config Presets

The app MUST load config presets from a bundled `presets.yaml` file.
`presets.yaml` MUST be co-located in `Sources/MLXManagerApp/` and loaded via `Bundle.module`.
Four presets MUST be present: 4-bit 40k, 4-bit 80k, 8-bit 40k, 8-bit 80k.

Each preset MUST include a `pythonPath` field (full path to the python binary for that preset's venv).
Missing `pythonPath` MUST throw `ConfigError.missingField("pythonPath")`.

#### Scenario: Preset loading

- GIVEN the bundled `presets.yaml` exists
- WHEN the app loads configs
- THEN it MUST return exactly 4 presets with correct model names and context sizes
- AND each preset MUST have a non-empty `pythonPath`

#### Scenario: 4-bit 40k preset args

- GIVEN the 4-bit 40k preset is loaded
- THEN it MUST include `--chat-template-args '{"enable_thinking":false}'` in its args
- AND `--trust-remote-code`

#### Scenario: Missing pythonPath

- GIVEN a preset YAML entry with no `pythonPath` field
- WHEN loaded
- THEN `ConfigLoader` MUST throw `ConfigError.missingField("pythonPath")`

---

### Requirement: Log Tailing

The app MUST tail the MLX server log file in real-time, parse new lines via `LogParser`, and emit `LogEvent` values to a caller-provided callback.

#### Scenario: Start tailing

- GIVEN a valid log file path
- WHEN `start()` is called
- THEN the tailer MUST seek to the end of the file and begin watching for changes

#### Scenario: New log lines

- GIVEN the tailer is running
- WHEN new lines are appended to the log file
- THEN each line MUST be parsed via `LogParser` and matching events emitted via the callback

#### Scenario: Non-matching lines

- GIVEN a non-parseable line is appended
- WHEN the tailer reads it
- THEN no event MUST be emitted

#### Scenario: Multiple lines in one write

- GIVEN multiple lines are appended atomically
- WHEN the tailer reads them
- THEN events MUST be emitted in the order the lines appear

#### Scenario: Partial lines

- GIVEN data is appended without a trailing newline
- WHEN the tailer reads it
- THEN the partial content MUST be buffered until a newline arrives

#### Scenario: File truncation

- GIVEN the log file is truncated (e.g. log rotation)
- WHEN the tailer detects the file is shorter than the last read offset
- THEN it MUST reset to offset 0 and read from the beginning

#### Scenario: Stop tailing

- GIVEN the tailer is running
- WHEN `stop()` is called
- THEN the file watcher MUST be stopped and resources released

#### Scenario: File not found

- GIVEN the log file does not exist
- WHEN `start()` is called
- THEN it MUST be a no-op (no crash, no watching started)

---

### Requirement: Request Recording

`ServerState` MUST track completed requests as `RequestRecord` values (startedAt, completedAt,
tokens, computed duration). `AppDelegate` drains `serverState.completedRequest` after each
event and appends to a history array (capped at 500).

#### Scenario: KV Caches completion produces a record

- GIVEN a progress event was received (setting `requestStartedAt`)
- WHEN a `KV Caches:` completion event arrives
- THEN `serverState.completedRequest` MUST be non-nil with the KV line's token count

#### Scenario: HTTP 200 completion produces a record

- GIVEN a progress event was received
- WHEN a `POST 200` completion event arrives
- THEN `serverState.completedRequest` MUST be non-nil

#### Scenario: Completion with no prior progress

- GIVEN no progress events have been received since the last completion
- WHEN a completion signal arrives
- THEN `serverState.completedRequest` MUST be nil (no request to record)

---

### Requirement: User Preset Persistence

The app MUST support user-editable presets persisted to `~/.config/mlx-manager/presets.yaml`.
`UserPresetStore.load()` reads the user file if present, otherwise falls back to bundled presets.
`UserPresetStore.save(_:)` writes presets to the user file via Yams.

#### Scenario: Load with no user file

- GIVEN `~/.config/mlx-manager/presets.yaml` does not exist
- WHEN `UserPresetStore.load()` is called
- THEN it MUST return the 4 bundled presets

#### Scenario: Save and reload

- GIVEN presets are saved via `UserPresetStore.save(_:)`
- WHEN `UserPresetStore.load()` is called
- THEN it MUST return the saved presets

---

### Requirement: App Settings

The app MUST persist user settings to `~/.config/mlx-manager/settings.json`.
`AppSettings` has two fields: `ramGraphEnabled` (default `false`) and `ramPollInterval`
(default `5`, allowed values: 2, 5, 10 seconds).

---

### Requirement: RAM Monitoring

The app MUST poll the server process's resident memory via `proc_pidinfo` at a configurable
interval, emitting `RAMSample` values (timestamp, GB) via callback.

#### Scenario: Polling emits samples

- GIVEN a `RAMPoller` is started with a valid PID
- WHEN the timer fires
- THEN `onSample` MUST be called with a `RAMSample` containing the process RSS in GB

---

### Requirement: UI Windows

The app MUST provide four windows accessible from the status bar menu:

1. **Log Viewer** — scrolling text view with colour-coded log lines, clear button, 10k line cap
2. **Request History** — bar chart of completed requests (height = tokens, opacity = duration)
3. **RAM Graph** — line chart of `RAMSample` values with total RAM dashed line (only shown when `ramGraphEnabled`)
4. **Settings** — tabbed window (Presets table + General settings), with environment install section

---

### Requirement: Menu Structure

The status bar menu MUST contain (in order):

- Preset header ("Start with:" when offline, "Switch to:" when running)
- Preset items (disabled + "(env missing)" suffix when `pythonPath` absent)
- Stop (only when running)
- Show Log, Request History
- RAM Graph (only when `ramGraphEnabled`)
- Settings…
- Quit

`StatusBarController` accepts a `fileExists: (String) -> Bool` dependency to check preset availability.

---

### Requirement: Environment Bootstrap

On first launch, the app MUST auto-detect a missing Python environment and install it.

#### Scenario: Environment missing on launch

- GIVEN `~/.mlx-manager/venv/bin/python` does not exist
- WHEN the app launches
- THEN it MUST show "Installing environment…" in the menu and run `EnvironmentBootstrapper`

#### Scenario: Environment already present

- GIVEN `~/.mlx-manager/venv/bin/python` exists
- WHEN the app launches
- THEN the bootstrap step MUST be skipped and presets shown normally

---

### Requirement: UV-Based Environment Bootstrapping

The environment installer MUST use `uv` (not `python3 -m venv` / `pip`) for faster,
version-pinned environments.

#### Scenario: uv found locally

- GIVEN `uv` exists at `~/.local/bin/uv` or `/opt/homebrew/bin/uv`
- WHEN the bootstrapper runs
- THEN it MUST skip the `uv` install step and proceed to `uv venv` + `uv pip install`

#### Scenario: uv not found

- GIVEN `uv` is not found at any candidate path
- WHEN the bootstrapper runs
- THEN it MUST install `uv` via `curl -LsSf https://astral.sh/uv/install.sh | sh`
- AND then proceed to `uv venv` + `uv pip install`

#### Scenario: Install steps

- The bootstrapper MUST run:
  1. `uv venv ~/.mlx-manager/venv --python 3.12`
  2. `uv pip install mlx-lm --python <venvPython>`
