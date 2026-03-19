# Tasks: Server Control

Each task = one RED test written and confirmed failing, then GREEN implementation.

## Setup

- [x] Create stub `Sources/MLXManager/ServerManager.swift` (protocols + empty class)
- [x] Create `Tests/MLXManagerTests/ServerManagerTests.swift` with all RED tests
- [x] Confirm `swift test` compiles — 8 new tests fail as expected (RED)

## Red-Green Cycles

- [x] **RED** `startAssemblesCorrectArguments` — mock captures args
- [x] **RED** `startSetsIsRunning` — isRunning is false
- [x] **RED** `startWhileRunningThrows` — no throw
- [x] **RED** `stopTerminatesProcess` — terminate not called
- [x] **RED** `stopSetsIsRunningFalse` — isRunning still true
- [x] **RED** `stopWhileNotRunningIsNoOp` — should not throw
- [x] **RED** `restartStopsAndStarts` — not implemented
- [x] **RED** `startIncludesExtraArgs` — extraArgs not passed
- [x] **GREEN** implement ServerManager: start/stop/restart with ProcessLauncher protocol

## Done

- [x] All tests green — 8 new ServerManager + 12 ServerState + 9 ConfigLoader + 13 LogParser
- [x] `swift test` output shows 0 failures
- [x] Commit: `feat(004-server-control): implement ServerManager`
