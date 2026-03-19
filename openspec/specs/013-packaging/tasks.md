# Tasks: App Bundle Packaging

**Change ID:** 013-packaging

## Code change — resource loading

- [x] T1: `AppDelegate.bundledPresetsURL()` returns `Bundle.module` URL when available, else `Bundle.main` URL
- [x] T2: `AppDelegate.loadPresets()` uses `bundledPresetsURL()` instead of inline `Bundle.module` call

> T1–T2 have no unit test: `Bundle.module` / `Bundle.main` are runtime-only. Verified manually.

## Static files

- [x] T3: Create `Resources/Info.plist` with correct keys (`LSUIElement=YES`, bundle ID, executable name, min OS 14.0)
- [x] T4: Create `Resources/LaunchAgent.plist` pointing to `/Applications/MLXManager.app/Contents/MacOS/MLXManager`

## Makefile

- [x] T5: `make build` runs `swift build -c release`
- [x] T6: `make bundle` assembles `build/MLXManager.app/Contents/{MacOS,Resources}`, copies binary, `Info.plist`, `presets.yaml`
- [x] T7: `make sign` ad-hoc signs `build/MLXManager.app`
- [x] T8: `make install` depends on `bundle sign`, copies to `/Applications`
- [x] T9: `make uninstall` removes `/Applications/MLXManager.app`
- [x] T10: `make launch-agent` copies plist to `~/Library/LaunchAgents/` and loads it
- [x] T11: `make remove-launch-agent` unloads and removes plist
- [x] T12: `make clean` removes `build/`
- [x] T13: default target (`all`) depends on `build bundle sign`

## AppSettings — startAtLogin field

- [x] T14: `AppSettings` gains `startAtLogin: Bool` defaulting to `false`
- [x] T15: `AppSettings` round-trips `startAtLogin` through JSON encode/decode

## LoginItemManager

- [x] T16: `LoginItemManager.enable()` copies `LaunchAgent.plist` to `~/Library/LaunchAgents/com.stefano.mlx-manager.plist` and calls `launchctl load`
- [x] T17: `LoginItemManager.disable()` calls `launchctl unload` and removes the plist
- [x] T18: `LoginItemManager.isEnabled()` returns `true` iff the plist file exists

## Settings UI

- [x] T19: "Start at login" checkbox appears in Settings > General, below RAM graph toggle
- [x] T20: checkbox initial state reflects `AppSettings.startAtLogin`
- [x] T21: on Save with toggle changed to on → `LoginItemManager.enable()` called
- [x] T22: on Save with toggle changed to off → `LoginItemManager.disable()` called

## Makefile — keep as dev convenience only

- [x] T10: `make launch-agent` copies plist to `~/Library/LaunchAgents/` and loads it (dev convenience)
- [x] T11: `make remove-launch-agent` unloads and removes plist (dev convenience)

## Manual verification

- [x] T23: `make install` → app launches from Spotlight, no Dock icon appears
- [x] T24: Settings > General > "Start at login" on → app starts on next login
- [x] T25: Settings > General > "Start at login" off → app no longer starts at login
- [x] T26: `make uninstall` → fully removed, no leftovers

(End of file - total 57 lines)
