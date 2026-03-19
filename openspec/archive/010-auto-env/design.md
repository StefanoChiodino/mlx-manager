# Design: 010-auto-env

## Components

### 1. `EnvironmentChecker` (new, `Sources/MLXManager/EnvironmentChecker.swift`)

Pure value-type helper. Injected `fileExists` closure for testability.

```swift
public struct EnvironmentChecker {
    public let fileExists: (String) -> Bool

    public init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:))

    /// Returns true when the python binary at `path` exists on disk.
    public func isReady(pythonPath: String) -> Bool
}
```

### 2. `StatusBarController` — new `.installingEnvironment` state

Add a `Bool` flag `isInstallingEnvironment` (internal). When `true`,
`rebuildMenu` replaces the preset section with a single disabled item
`"Installing environment…"`.

New public methods:

```swift
public func environmentInstallStarted()
public func environmentInstallFinished()
```

### 3. `AppDelegate` — bootstrap in `applicationDidFinishLaunching`

```swift
private func bootstrapEnvironmentIfNeeded() {
    let checker = EnvironmentChecker()
    guard !checker.isReady(pythonPath: EnvironmentInstaller.venvPath + "/bin/python") else { return }
    statusBarController.environmentInstallStarted()
    let inst = EnvironmentInstaller()
    inst.onComplete = { [weak self] _ in
        self?.statusBarController.environmentInstallFinished()
    }
    inst.install()
    self.backgroundInstaller = inst   // retain until done
}
```

`AppDelegate` gains a `private var backgroundInstaller: EnvironmentInstaller?` property.

## Data Flow

```
applicationDidFinishLaunching
  → bootstrapEnvironmentIfNeeded()
      → EnvironmentChecker.isReady → false
      → statusBarController.environmentInstallStarted()  [menu shows "Installing…"]
      → EnvironmentInstaller.install() (background thread)
          → onComplete(success)
          → statusBarController.environmentInstallFinished()  [menu rebuilt, presets enabled]
```

## Tests

All tests are unit tests in `MLXManagerTests`.

| # | File | Test method | Behaviour |
|---|------|-------------|-----------|
| T1 | `EnvironmentCheckerTests` | `test_isReady_whenPythonExists_returnsTrue` | fileExists returns true → isReady true |
| T2 | `EnvironmentCheckerTests` | `test_isReady_whenPythonMissing_returnsFalse` | fileExists returns false → isReady false |
| T3 | `StatusBarControllerTests` | `test_environmentInstallStarted_showsInstallingItem` | menu has "Installing environment…" item |
| T4 | `StatusBarControllerTests` | `test_environmentInstallFinished_showsPresets` | menu shows preset items again |
