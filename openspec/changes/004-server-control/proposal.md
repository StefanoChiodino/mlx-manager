# Proposal: Server Control

## Problem

The app needs to start, stop, and restart the MLX server process (`mlx_lm.server`) using a selected config preset. Currently there is no process management.

## Solution

Implement `ServerManager` — a class that spawns `mlx_lm.server` via `Process`, tracks the running process, and can terminate it. Uses a `ProcessLauncher` protocol so tests can inject a mock instead of spawning real processes.

## Scope

- `ProcessLauncher` protocol (abstraction over `Foundation.Process`)
- `ServerManager` class with start/stop/restart
- CLI argument assembly from `ServerConfig`
- Full test coverage with mock launcher

## Out of Scope

- Log tailing (future change — `LogTailer`)
- UI integration (menu bar controls)
- Server health checks
