# Design: Process Scanner — PID-File-Free Server Detection

**Change ID:** 019-process-scanner

## New Types

### `DiscoveredProcess`

```swift
/// A running mlx_lm.server process found by the scanner.
public struct DiscoveredProcess: Equatable {
    public let pid: Int32
    public let port: Int       // parsed from --port argv, defaults to 8080
}
```

### `ProcessArgvReading` (protocol — for testability)

```swift
/// Reads the argument vector of a running process by PID.
/// Real implementation uses sysctl(KERN_PROCARGS2).
/// Tests inject a stub.
public protocol ProcessArgvReading {
    /// Returns the argv array for the given PID, or nil if unavailable.
    func argv(for pid: Int32) -> [String]?
}
```

### `SystemProcessArgvReader` (production implementation)

```swift
public struct SystemProcessArgvReader: ProcessArgvReading {
    public func argv(for pid: Int32) -> [String]? {
        // 1. Call sysctl([CTL_KERN, KERN_PROCARGS2], pid) to get raw bytes
        // 2. Skip the argc Int32 at offset 0
        // 3. Skip the null-terminated executable path
        // 4. Parse remaining null-separated strings as argv
        // Returns nil on any error (permission denied, process gone, etc.)
    }
}
```

### `ProcessScanner`

```swift
/// Scans all running processes and returns the first one identified as
/// an mlx_lm.server instance.
public struct ProcessScanner {
    private let pidLister: PIDListing      // injectable for tests
    private let argvReader: ProcessArgvReading

    public init(
        pidLister: PIDListing = SystemPIDLister(),
        argvReader: ProcessArgvReading = SystemProcessArgvReader()
    )

    /// Returns the first discovered mlx_lm.server process, or nil.
    public func findMLXServer() -> DiscoveredProcess?
}
```

### `PIDListing` (protocol — for testability)

```swift
public protocol PIDListing {
    /// Returns all PIDs currently running on the system.
    func allPIDs() -> [Int32]
}

public struct SystemPIDLister: PIDListing {
    public func allPIDs() -> [Int32] {
        // proc_listallpids(nil, 0) to get count, then allocate and fill
    }
}
```

## Detection Logic

A process is an MLX server if its argv satisfies **either**:

```
argv.contains("-m") && argv.dropFirst(argv.firstIndex(of: "-m")! + 1).first == "mlx_lm.server"
```
or
```
argv.contains("mlx_lm.server")
```
or any element ends with `mlx_lm/server.py`.

Port extraction:
```
if let idx = argv.firstIndex(of: "--port"), argv.indices.contains(idx + 1) {
    port = Int(argv[idx + 1]) ?? 8080
} else {
    port = 8080
}
```

## Deletions

- `Sources/MLXManager/PIDFile.swift` — deleted
- `Sources/MLXManager/PIDRecovery.swift` — deleted
- `Tests/MLXManagerTests/PIDFileTests.swift` — deleted
- `Tests/MLXManagerTests/PIDRecoveryTests.swift` — deleted

## ServerManager changes

- Remove `pidFile: PIDFileWriting?` parameter from `init`
- Remove `pidFile.write(pid:)` call after launch
- Remove `pidFile.delete()` calls in `stop()` and `onExit`
- `adoptProcess(pid:)` gains an optional `port: Int = 8080` parameter
  (stored alongside `adoptedPID` for future use)

## AppDelegate changes

```swift
// Replace:
let result = PIDRecovery().recover(pidFile: PIDFile(url: pidFileURL))

// With:
let result = ProcessScanner().findMLXServer()
if let found = result {
    serverManager.adoptProcess(pid: found.pid, port: found.port)
}
```

## Data Flow

```
App Launch
    │
    ▼
ProcessScanner.findMLXServer()
    │
    ├── nil ──────────────────► normal startup (offline)
    └── DiscoveredProcess ────► ServerManager.adoptProcess(pid:port:)
                                    │
                                    ▼
                               UI shows idle, log tailing starts
```

## Test Strategy

Every component is tested through its injected protocol:

| Test class | What is tested |
|-----------|---------------|
| `ProcessScannerTests` | Detection logic — stubs `PIDListing` + `ProcessArgvReading` |
| `SystemProcessArgvReaderTests` | sysctl parsing — reads argv of the test process itself (known) |
| `DiscoveredProcessTests` | Port defaulting, equality |
| `ServerManagerTests` (existing) | Updated to remove PIDFile expectations |
| `AppDelegateTests` (existing) | Updated to inject stub scanner |

### Key test cases for `ProcessScanner`

```
test_findMLXServer_noProcesses_returnsNil
test_findMLXServer_noMLXProcess_returnsNil
test_findMLXServer_mlxModuleInArgv_returnsDiscoveredProcess
test_findMLXServer_mlxScriptPathInArgv_returnsDiscoveredProcess
test_findMLXServer_customPort_extractsPort
test_findMLXServer_noPortFlag_defaultsTo8080
test_findMLXServer_multipleProcesses_returnsFirst
test_findMLXServer_argvUnavailable_skipsProcess
```

### Key test cases for `SystemProcessArgvReader`

```
test_argv_currentProcess_containsTestExecutablePath
test_argv_nonExistentPID_returnsNil
```

## Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| argv unavailable (permission denied) | `argv(for:)` returns nil → process skipped |
| Process exits during scan | sysctl returns error → nil → skipped |
| Port flag present but no value follows | Default 8080 used |
| Port value is non-numeric | Default 8080 used |
| Multiple MLX servers | First found is returned (undefined order) |
