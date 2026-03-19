# Tasks: 007-python-path-and-exit

Each task = one RED test confirmed failing, then GREEN implementation.

## Config: pythonPath field

- [x] **RED** `test_load_allPresets_havePythonPath` — `ServerConfig` had no `pythonPath`; test failed to compile
- [x] **GREEN** add `pythonPath: String` to `ServerConfig`; parse from YAML in `ConfigLoader`
- [x] **RED** `test_load_missingPythonPathField_throwsMissingField` — no validation existed; test failed
- [x] **GREEN** add `guard let pythonPath` with `throw ConfigError.missingField("pythonPath")`

## ServerManager: pythonPath as command

- [x] **RED** `start uses pythonPath from config as the command` — `ServerManager` launched hardcoded `"python"`; test failed
- [x] **GREEN** replace hardcoded command with `config.pythonPath` in `ServerManager.start`

## ServerManager: onExit callback

- [x] **RED** `onExit is called when process terminates` — `ProcessLauncher.launch` had no `onExit` param; `ServerManager` had no `onExit` property; test failed to compile
- [x] **GREEN** add `onExit` param to `ProcessLauncher.launch`; add `public var onExit` to `ServerManager`; wire callback through `launch`

## App wiring and bundle fix

- [x] Wire `serverManager.onExit` in `AppDelegate` → `handleProcessExit()`
- [x] Wire `Process.terminationHandler` → `onExit` in `RealProcessLauncher`
- [x] Move `presets.yaml` to `Sources/MLXManagerApp/`; update `Package.swift`
- [x] Switch `AppDelegate` from `Bundle.main` to `Bundle.module`

## Done

- [x] All tests green — 64/64
- [x] `swift test` output shows 0 failures
