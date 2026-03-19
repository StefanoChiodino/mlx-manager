# Proposal: 011-uv-env — Replace venv/pip with uv

## Problem

Change 010-auto-env bootstraps the environment using `/usr/bin/python3 -m venv`
and `pip`. This has two failure modes:

1. `/usr/bin/python3` is the macOS stub (Python 3.9.6 via Xcode CLT) — it may
   prompt the user to install Xcode Command Line Tools on a fresh machine.
2. `pip` is slow compared to `uv` and provides no Python version pinning.

Additionally, 010's `EnvironmentInstaller` has no way to install `uv` itself —
it assumes both python3 and pip are already working.

## Proposed Solution

Replace the two-step `python3 -m venv` + `pip install` flow with `uv`:

**Step 1 — Locate or install uv**

Search for `uv` in order:
1. `~/.local/bin/uv` (official installer default)
2. `/opt/homebrew/bin/uv` (Homebrew)
3. Any `uv` on `$PATH` via `/usr/bin/env uv`

If none found, install uv using its official installer script:
`curl -LsSf https://astral.sh/uv/install.sh | sh`

The installer places the binary at `~/.local/bin/uv`. No sudo required.

**Step 2 — Create venv**

`uv venv ~/.mlx-manager/venv --python 3.12`

uv will download Python 3.12 automatically if not present — no Xcode CLT needed.

**Step 3 — Install mlx-lm**

`uv pip install mlx-lm --python ~/.mlx-manager/venv/bin/python`

## Key Design Decisions

- `EnvironmentInstaller` gains a `uvPath` discovery step (injectable for tests)
- The `--python 3.12` pin ensures mlx-lm gets a compatible, known-good Python
- uv install step uses `sh -c "curl ... | sh"` so we don't need to hard-code
  the installer binary path

## Out of Scope

- Auto-upgrade of uv itself
- Pinning uv version
- Offline installation
