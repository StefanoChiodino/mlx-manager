# Design: 011-uv-env

## Components

### 1. `UVLocator` (new, `Sources/MLXManager/UVLocator.swift`)

Pure struct. Finds the `uv` binary. Injectable `fileExists` for tests.

```swift
public struct UVLocator {
    public static let candidatePaths = [
        NSString("~/.local/bin/uv").expandingTildeInPath,
        "/opt/homebrew/bin/uv",
    ]

    public let fileExists: (String) -> Bool

    public init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:))

    /// Returns the first candidate path that exists, or nil if uv is not found.
    public func locate() -> String?
}
```

### 2. `EnvironmentInstaller` — replace internals

Replace the existing two-step flow with:

```
Step 1: locate uv  → if nil, run uv install script
Step 2: uv venv ~/.mlx-manager/venv --python 3.12
Step 3: uv pip install mlx-lm --python <venvPython>
```

No changes to public interface (`install()`, `cancel()`, `onOutput`, `onComplete`).

New internal property: `uvInstallerScript = "curl -LsSf https://astral.sh/uv/install.sh | sh"`

The `runStep` method signature stays the same; Step 1 uses `sh -c "curl ... | sh"`.

After Step 1 the uv path is re-resolved (installer places it at `~/.local/bin/uv`).

### 3. `EnvironmentChecker` — no change

Still checks `fileExists(pythonPath)`. No changes needed.

### 4. `AppDelegate` / `StatusBarController` — no change

The public contract of `EnvironmentInstaller` is unchanged.

## Tests

| # | File | Test method | Behaviour |
|---|------|-------------|-----------|
| T1 | `UVLocatorTests` | `test_locate_whenFirstCandidateExists_returnsIt` | first hit wins |
| T2 | `UVLocatorTests` | `test_locate_whenFirstMissingSecondExists_returnsSecond` | fallback works |
| T3 | `UVLocatorTests` | `test_locate_whenNoneExist_returnsNil` | nil when absent |
| T4 | `EnvironmentInstallerTests` | `test_install_whenUVFound_skipsInstallStep` | no curl when uv present |
| T5 | `EnvironmentInstallerTests` | `test_install_whenUVMissing_runsInstallStep` | curl runs when uv absent |
| T6 | `EnvironmentInstallerTests` | `test_install_usesUVVenvAndUVPipInstall` | correct commands used |

Note: `EnvironmentInstaller` lives in `MLXManagerApp` and is not directly
testable. The testable core logic is extracted into a new
`EnvironmentBootstrapper` in `MLXManager`, which accepts an injected
`CommandRunner` protocol.

```swift
public protocol CommandRunner {
    /// Run a shell command synchronously. Returns exit code.
    func run(command: String, arguments: [String], onOutput: @escaping (String) -> Void) -> Int32
}
```

`EnvironmentInstaller` (in `MLXManagerApp`) becomes a thin adapter that creates
an `EnvironmentBootstrapper` with a real `ProcessCommandRunner` and delegates
`install()` / `cancel()` to it.

Production `ProcessCommandRunner` wraps `Process`; test `SpyCommandRunner`
records every call made.
