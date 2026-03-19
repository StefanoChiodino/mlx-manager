# Proposal: 010-auto-env — Automatic Environment Bootstrap

## Problem

On first launch (and whenever `~/.mlx-manager/venv/bin/python` is absent), every
preset is shown as `(env missing)` and disabled in the menu. The user has no path
to fix this except opening Settings and clicking "Install / Reinstall mlx-lm"
manually — and even then they must know it exists.

## Proposed Solution

1. **Auto-detect** on launch: check whether `EnvironmentInstaller.pythonPath` exists.
2. **Auto-install** if missing: run `EnvironmentInstaller.install()` in the background
   immediately after launch, with no user interaction required.
3. **Rebuild menu** once installation completes: call
   `StatusBarController.rebuildMenu` so the presets become enabled automatically.
4. **Auto-update** if outdated: after a successful server start, if `mlx-lm` is
   present but a newer version exists on PyPI, run `pip install --upgrade mlx-lm`
   in the background (silent, no UI).  *(stretch — excluded from initial scope)*

## Scope (initial)

- New type `EnvironmentChecker` (in `MLXManager` target, testable) with one
  method: `isReady(pythonPath:) -> Bool` — wraps `FileManager.fileExists`.
- `AppDelegate.applicationDidFinishLaunching` calls `EnvironmentChecker.isReady`
  and, if false, kicks off `EnvironmentInstaller.install()`.
- On install completion (success or failure) the status bar menu is rebuilt so
  the user sees updated enabled/disabled state without manual interaction.
- A brief "Installing environment…" disabled menu item is shown while install is
  in progress (replaces the per-preset `(env missing)` label while busy).

## Out of Scope

- Auto-update of mlx-lm
- Progress reporting in menu beyond busy/done
- Multiple venv paths (only the default `~/.mlx-manager/venv` is managed)
