# Core Spec — MLX Manager

## Requirements

### Requirement: Menu Bar Presence
The app MUST display a single icon in the macOS status bar at all times while running.

### Requirement: Server Status Display
The menu bar icon MUST reflect the current server state:
- Stopped — server process is not running
- Running / Idle — server is running, no active request
- Processing — server is actively processing a request (show percentage)

#### Scenario: Server not running
- GIVEN the MLX server process is not running
- WHEN the menu bar icon is rendered
- THEN it MUST show a stopped/offline indicator

#### Scenario: Server idle
- GIVEN the server is running and no progress lines have appeared recently
- WHEN the menu bar icon is rendered
- THEN it MUST show a running/idle indicator

#### Scenario: Server processing
- GIVEN a `Prompt processing progress: X/Y` line has been parsed
- WHEN the menu bar icon is rendered
- THEN it MUST show the percentage `(X/Y * 100)%`

---

### Requirement: Log Parsing — Progress
The log parser MUST extract progress from lines matching:
`Prompt processing progress: <current>/<total>`

#### Scenario: Valid progress line
- GIVEN a log line `Prompt processing progress: 4096/8333`
- WHEN parsed
- THEN the result MUST have `current = 4096`, `total = 8333`, `percentage ≈ 49.2`

#### Scenario: Progress at completion
- GIVEN a log line `Prompt processing progress: 8333/8333`
- WHEN parsed
- THEN `isComplete` MUST be `true`

#### Scenario: Non-progress line
- GIVEN a log line that does not match the progress pattern
- WHEN parsed for progress
- THEN the result MUST be `nil`

---

### Requirement: Log Parsing — KV Cache
The log parser MUST extract GPU memory and token count from lines matching:
`KV Caches: <n> seq, <gb> GB, latest user cache <tokens> tokens`

#### Scenario: Valid KV Caches line
- GIVEN a log line `KV Caches: 4 seq, 1.94 GB, latest user cache 25724 tokens`
- WHEN parsed
- THEN the result MUST have `gpuGB = 1.94`, `tokens = 25724`

#### Scenario: Non-KV line
- GIVEN a log line that does not match the KV pattern
- WHEN parsed for KV data
- THEN the result MUST be `nil`

---

### Requirement: Log Parsing — Ignored Lines
The log parser MUST return `nil` for lines that are not actionable:
- HTTP request lines (`POST /v1/chat/completions`)
- Fetching/download progress lines
- WARNING lines
- resource_tracker lines

---

### Requirement: Server Control — Start
The app MUST be able to start the MLX server with a selected config preset.

#### Scenario: Start with preset
- GIVEN a valid config preset is selected
- WHEN the user clicks Start
- THEN the server process MUST be launched with the correct arguments

---

### Requirement: Server Control — Stop
The app MUST be able to stop a running MLX server process.

#### Scenario: Stop running server
- GIVEN the server process is running
- WHEN the user clicks Stop
- THEN the process MUST be terminated

---

### Requirement: Server Control — Restart
The app MUST support restarting the server (stop then start with same config).

---

### Requirement: Config Presets
The app MUST load config presets from a bundled `presets.yaml` file.
Four presets MUST be present: 4-bit 40k, 4-bit 80k, 8-bit 40k, 8-bit 80k.

#### Scenario: Preset loading
- GIVEN the bundled `presets.yaml` exists
- WHEN the app loads configs
- THEN it MUST return exactly 4 presets with correct model names and context sizes
