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

## Manual verification

- [ ] T14: `make install` → app launches from Spotlight, no Dock icon appears
- [ ] T15: `make launch-agent` → app starts on next login session
- [ ] T16: `make uninstall && make remove-launch-agent` → fully removed, no leftovers
