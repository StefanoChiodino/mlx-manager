# Proposal: App Bundle Packaging

**Change ID:** 013-packaging
**Status:** proposed

## Problem

The app is currently built as a plain SwiftPM executable. It cannot be run as a proper macOS app:

- No `.app` bundle → can't be launched from Finder or Spotlight
- No `Info.plist` → macOS won't suppress the Dock icon (`LSUIElement`)
- No code signing → Gatekeeper blocks it on first run
- No login item support → must be started manually after every reboot

## Proposed Solution

Add a `Makefile` that wraps the SwiftPM build into a properly structured `.app` bundle, with an `Info.plist` and ad-hoc code signing. Optionally install a `LaunchAgent` plist for auto-start at login.

No Xcode project, no SPM plugin — just a Makefile and a handful of static files in `Resources/`.

## What Changes

### New files

| File | Purpose |
|------|---------|
| `Resources/Info.plist` | Bundle metadata: `LSUIElement=YES`, bundle ID, version |
| `Makefile` | `build`, `bundle`, `install`, `uninstall`, `launch-agent` targets |
| `Resources/LaunchAgent.plist` | Template `com.user.mlx-manager` LaunchAgent (optional install) |

### Makefile targets

| Target | What it does |
|--------|-------------|
| `make build` | `swift build -c release` |
| `make bundle` | Assembles `MLXManager.app` in `./build/` |
| `make sign` | Ad-hoc signs the bundle (`codesign --force --deep -s -`) |
| `make install` | Copies bundle to `/Applications`, signs it |
| `make uninstall` | Removes bundle from `/Applications` |
| `make launch-agent` | Installs LaunchAgent plist + loads it via `launchctl` |
| `make remove-launch-agent` | Unloads and removes LaunchAgent |

### `.app` bundle layout

```
MLXManager.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── MLXManager          ← SwiftPM release binary
    └── Resources/
        └── presets.yaml        ← copied from Sources/MLXManagerApp/
```

## Out of scope

- Notarization / Apple Developer signing (personal use only)
- Auto-update mechanism
- DMG packaging

## Acceptance criteria

1. `make install` produces a working `/Applications/MLXManager.app` that launches from Spotlight
2. The app does NOT appear in the Dock
3. The bundle is ad-hoc signed (passes Gatekeeper for locally-built apps)
4. `make launch-agent` makes the app start automatically at login
5. `make uninstall` + `make remove-launch-agent` cleanly removes everything
