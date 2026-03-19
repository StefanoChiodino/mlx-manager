# Design: App Bundle Packaging

**Change ID:** 013-packaging

## Overview

Three concerns:

1. **Static resources** — `presets.yaml` is currently loaded via `Bundle.module` (SPM-generated). In a `.app` bundle, there is no SPM bundle sidecar; we must load from `Bundle.main`. `AppDelegate.loadPresets()` needs to fall back to `Bundle.main` when `Bundle.module` fails.

2. **Bundle assembly** — A `Makefile` copies the SwiftPM release binary + `Info.plist` + `presets.yaml` into the correct `.app` layout, then ad-hoc signs.

3. **Login item** — Managed via a toggle in Settings > General, not a terminal command. The Makefile retains `launch-agent` / `remove-launch-agent` as developer convenience targets only.

---

## Resource loading change

`AppDelegate.loadPresets()` currently does:

```swift
guard let url = Bundle.module.url(forResource: "presets", withExtension: "yaml")
```

`Bundle.module` is a synthesised property on the `MLXManagerApp` target's generated bundle accessor. It works under `swift run` / `swift test` but is unavailable when the binary runs outside an SPM build tree.

**Fix:** add a fallback to `Bundle.main`:

```swift
private func bundledPresetsURL() -> URL? {
    // SPM dev build
    if let url = Bundle.module.url(forResource: "presets", withExtension: "yaml") { return url }
    // .app bundle (Contents/Resources/)
    return Bundle.main.url(forResource: "presets", withExtension: "yaml")
}
```

No new types. One small method extracted from `loadPresets()`.

---

## File layout

### New source files

```
Resources/
├── Info.plist          ← app bundle metadata
└── LaunchAgent.plist   ← login item template
Makefile
```

`presets.yaml` stays in `Sources/MLXManagerApp/` (SPM still uses it). The Makefile also copies it into the bundle.

### `.app` bundle layout produced by `make bundle`

```
build/MLXManager.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── MLXManager
    └── Resources/
        └── presets.yaml
```

---

## Info.plist

Key fields:

| Key | Value |
|-----|-------|
| `CFBundleName` | `MLXManager` |
| `CFBundleIdentifier` | `com.stefano.mlx-manager` |
| `CFBundleVersion` | `1` |
| `CFBundleShortVersionString` | `1.0` |
| `CFBundleExecutable` | `MLXManager` |
| `CFBundlePackageType` | `APPL` |
| `LSUIElement` | `YES` ← suppresses Dock icon |
| `NSHighResolutionCapable` | `YES` |
| `LSMinimumSystemVersion` | `14.0` |

---

## LaunchAgent.plist

Installed to `~/Library/LaunchAgents/com.stefano.mlx-manager.plist`.

```xml
<key>Label</key>      <string>com.stefano.mlx-manager</string>
<key>ProgramArguments</key>
  <array><string>/Applications/MLXManager.app/Contents/MacOS/MLXManager</string></array>
<key>RunAtLoad</key>  <true/>
<key>KeepAlive</key>  <false/>
```

---

## Makefile targets

| Target | Command summary |
|--------|----------------|
| `build` | `swift build -c release` |
| `bundle` | mkdir layout, copy binary + plists + yaml |
| `sign` | `codesign --force --deep -s - build/MLXManager.app` |
| `install` | `bundle` + `sign` + `cp -r` to `/Applications` |
| `uninstall` | `rm -rf /Applications/MLXManager.app` |
| `launch-agent` | `cp` plist to `~/Library/LaunchAgents/`, `launchctl load` |
| `remove-launch-agent` | `launchctl unload`, `rm` plist |
| `clean` | `rm -rf build/` |
| `all` (default) | `build bundle sign` |

---

## Start at Login — Settings UI

`AppSettings` gains a new field `startAtLogin: Bool` (default `false`).

`LoginItemManager` is a new type (in `MLXManagerApp`) responsible for installing and removing the LaunchAgent plist:

```swift
enum LoginItemManager {
    static func enable()   // copy LaunchAgent.plist to ~/Library/LaunchAgents/, launchctl load
    static func disable()  // launchctl unload, remove plist
    static func isEnabled() -> Bool  // plist file exists
}
```

`SettingsWindowController` adds a "Start at login" checkbox to the General tab (below the RAM graph toggle). On Save, if the value changed:

- toggled on  → `LoginItemManager.enable()`
- toggled off → `LoginItemManager.disable()`

`AppSettings.startAtLogin` is persisted to `~/.config/mlx-manager/settings.json` like existing fields. It is the source of truth for the checkbox initial state, not the filesystem.

The `Resources/LaunchAgent.plist` file already in the repo is used as the source for `LoginItemManager.enable()` — loaded from `Bundle.main` (in `.app`) with the same `bundledPresetsURL`-style fallback to `Bundle.module` for dev builds.

### LaunchAgent plist source

```swift
static func plistSourceURL() -> URL? {
    if let url = Bundle.main.url(forResource: "LaunchAgent", withExtension: "plist") { return url }
    // Dev fallback: look relative to executable
    return Bundle.module.url(forResource: "LaunchAgent", withExtension: "plist")
}
```

> The plist must be in the app bundle's `Contents/Resources/`. The Makefile already copies it there.

## No TDD for Makefile/plist files

These are build-system artefacts, not logic units. `LoginItemManager` shell-calls `launchctl` and touches `~/Library/LaunchAgents/` — not unit-testable. Acceptance is manual.

## Manual verification

1. `make install` → `/Applications/MLXManager.app` opens from Spotlight, no Dock icon
2. Settings > General > "Start at login" on → app starts on next login
3. Settings > General > "Start at login" off → app no longer starts at login
4. `make uninstall` → fully removed
