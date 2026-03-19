# Tasks: 010-auto-env

## T1 — EnvironmentChecker: isReady returns true when python exists
- [x] RED: write `test_isReady_whenPythonExists_returnsTrue` — expect `true`
- [x] GREEN: implement `EnvironmentChecker.isReady`

## T2 — EnvironmentChecker: isReady returns false when python missing
- [x] RED: write `test_isReady_whenPythonMissing_returnsFalse` — expect `false`
- [x] GREEN: (covered by T1 implementation)

## T3 — StatusBarController: shows "Installing environment…" during install
- [x] RED: write `test_environmentInstallStarted_showsInstallingItem`
- [x] GREEN: implement `environmentInstallStarted()` + `isInstallingEnvironment` flag in `rebuildMenu`

## T4 — StatusBarController: shows presets again after install finishes
- [x] RED: write `test_environmentInstallFinished_showsPresets`
- [x] GREEN: implement `environmentInstallFinished()`

## T5 — AppDelegate wiring (integration, manual verification only)
- [x] Add `backgroundInstaller` property to `AppDelegate`
- [x] Call `bootstrapEnvironmentIfNeeded()` in `applicationDidFinishLaunching`
