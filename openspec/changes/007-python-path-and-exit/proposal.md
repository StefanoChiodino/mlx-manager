# Proposal: Python Path and Process Exit

## Problem

Two gaps exist after changes 002 and 004:

1. **Hardcoded python command.** `ServerManager` launches `python` regardless of which venv the MLX server lives in. The real server lives at `~/repos/mlx/venv/bin/python3`. A different machine or venv layout breaks it silently.

2. **No process-exit notification.** When the MLX server crashes or is killed externally, `ServerManager` has no way to notify the app. The menu bar stays in the "running" state indefinitely.

3. **Resource bundle path wrong.** `AppDelegate` used `Bundle.main` to load `presets.yaml`, which fails in a SwiftPM executable. `Bundle.module` is required, and `presets.yaml` must be co-located with the app target source.

## Solution

1. Add `pythonPath: String` to `ServerConfig` and parse it from YAML (required field). Each preset declares the full path to its python binary. `ServerManager` uses it as the launch command.

2. Add `onExit: (() -> Void)?` to `ServerManager`. Thread it through `ProcessLauncher.launch` so `RealProcessLauncher` can wire `Process.terminationHandler` → the callback. `AppDelegate` uses it to clean up state.

3. Move `presets.yaml` to `Sources/MLXManagerApp/` and update `Package.swift` to `.copy("presets.yaml")`. Switch `AppDelegate` to `Bundle.module`.

## Scope

- `ServerConfig`: add `pythonPath`
- `ConfigLoader`: parse and require `pythonPath`
- `ProcessLauncher`: add `onExit` parameter to `launch`
- `ServerManager`: add `onExit` property; use `config.pythonPath` as command
- `RealProcessLauncher`: wire `terminationHandler`
- `AppDelegate`: wire `serverManager.onExit`; switch to `Bundle.module`
- `Package.swift`: fix resource path
- Tests: new cases for `pythonPath` and `onExit`

## Out of Scope

- Health-check polling
- Restart-on-crash logic
