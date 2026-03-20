import Testing
@testable import MLXManager

// MARK: - Test Doubles

final class StubPIDLister: PIDListing {
    var pids: [Int32]
    init(_ pids: [Int32] = []) { self.pids = pids }
    func allPIDs() -> [Int32] { pids }
}

final class StubProcessArgvReader: ProcessArgvReading {
    /// Map from PID → argv. If PID is absent, returns nil.
    var table: [Int32: [String]]
    init(_ table: [Int32: [String]] = [:]) { self.table = table }
    func argv(for pid: Int32) -> [String]? { table[pid] }
}

// MARK: - T1: DiscoveredProcess

@Suite("DiscoveredProcess")
struct DiscoveredProcessTests {

    @Test("equality: same pid and port are equal")
    func test_discoveredProcess_equality() {
        let a = DiscoveredProcess(pid: 100, port: 8080)
        let b = DiscoveredProcess(pid: 100, port: 8080)
        #expect(a == b)
    }

    @Test("inequality: different pid")
    func test_discoveredProcess_differentPID_notEqual() {
        let a = DiscoveredProcess(pid: 100, port: 8080)
        let b = DiscoveredProcess(pid: 200, port: 8080)
        #expect(a != b)
    }

    @Test("inequality: different port")
    func test_discoveredProcess_differentPort_notEqual() {
        let a = DiscoveredProcess(pid: 100, port: 8080)
        let b = DiscoveredProcess(pid: 100, port: 9000)
        #expect(a != b)
    }
}

// MARK: - ProcessScanner

@Suite("ProcessScanner")
struct ProcessScannerTests {

    // T4
    @Test("no processes — returns nil")
    func test_findMLXServer_noProcesses_returnsNil() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([]),
            argvReader: StubProcessArgvReader([:])
        )
        #expect(scanner.findMLXServer() == nil)
    }

    // T5
    @Test("processes present but none match — returns nil")
    func test_findMLXServer_noMLXProcess_returnsNil() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([1, 2]),
            argvReader: StubProcessArgvReader([
                1: ["/usr/bin/python3", "some_other_module"],
                2: ["/bin/bash", "-c", "echo hello"]
            ])
        )
        #expect(scanner.findMLXServer() == nil)
    }

    // T6
    @Test("argv contains mlx_lm.server as -m argument — returns DiscoveredProcess")
    func test_findMLXServer_mlxModuleInArgv_returnsDiscoveredProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([42]),
            argvReader: StubProcessArgvReader([
                42: ["/usr/bin/python3", "-m", "mlx_lm.server", "--port", "8080"]
            ])
        )
        #expect(scanner.findMLXServer() == DiscoveredProcess(pid: 42, port: 8080))
    }

    // T7
    @Test("argv contains mlx_lm.server as bare element — returns DiscoveredProcess")
    func test_findMLXServer_mlxServerBareArgv_returnsDiscoveredProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([7]),
            argvReader: StubProcessArgvReader([
                7: ["mlx_lm.server", "--port", "8080"]
            ])
        )
        #expect(scanner.findMLXServer() == DiscoveredProcess(pid: 7, port: 8080))
    }

    // T8
    @Test("argv contains path ending in mlx_lm/server.py — returns DiscoveredProcess")
    func test_findMLXServer_mlxScriptPathInArgv_returnsDiscoveredProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([9]),
            argvReader: StubProcessArgvReader([
                9: ["/home/user/.venv/bin/python3", "/home/user/.venv/lib/python3.11/site-packages/mlx_lm/server.py", "--port", "8080"]
            ])
        )
        #expect(scanner.findMLXServer() == DiscoveredProcess(pid: 9, port: 8080))
    }

    // T9
    @Test("--port 9000 in argv — port == 9000")
    func test_findMLXServer_customPort_extractsPort() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([5]),
            argvReader: StubProcessArgvReader([
                5: ["/usr/bin/python3", "-m", "mlx_lm.server", "--port", "9000"]
            ])
        )
        #expect(scanner.findMLXServer()?.port == 9000)
    }

    // T10
    @Test("no --port flag — defaults to 8080")
    func test_findMLXServer_noPortFlag_defaultsTo8080() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([5]),
            argvReader: StubProcessArgvReader([
                5: ["/usr/bin/python3", "-m", "mlx_lm.server"]
            ])
        )
        #expect(scanner.findMLXServer()?.port == 8080)
    }

    // T11
    @Test("--port is last element (no value) — defaults to 8080")
    func test_findMLXServer_portFlagNoValue_defaultsTo8080() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([5]),
            argvReader: StubProcessArgvReader([
                5: ["/usr/bin/python3", "-m", "mlx_lm.server", "--port"]
            ])
        )
        #expect(scanner.findMLXServer()?.port == 8080)
    }

    // T12
    @Test("--port abc (non-numeric) — defaults to 8080")
    func test_findMLXServer_portFlagNonNumeric_defaultsTo8080() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([5]),
            argvReader: StubProcessArgvReader([
                5: ["/usr/bin/python3", "-m", "mlx_lm.server", "--port", "abc"]
            ])
        )
        #expect(scanner.findMLXServer()?.port == 8080)
    }

    // T13
    @Test("argv returns nil for a PID — skips that process")
    func test_findMLXServer_argvUnavailable_skipsProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([1, 2]),
            argvReader: StubProcessArgvReader([
                // PID 1 has no entry → returns nil
                2: ["/usr/bin/python3", "-m", "mlx_lm.server", "--port", "8080"]
            ])
        )
        #expect(scanner.findMLXServer() == DiscoveredProcess(pid: 2, port: 8080))
    }

    // T14
    @Test("multiple processes, first is MLX — returns first")
    func test_findMLXServer_multipleProcesses_returnsFirst() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([10, 20]),
            argvReader: StubProcessArgvReader([
                10: ["/usr/bin/python3", "-m", "mlx_lm.server", "--port", "8080"],
                20: ["/usr/bin/python3", "-m", "mlx_lm.server", "--port", "9000"]
            ])
        )
        #expect(scanner.findMLXServer() == DiscoveredProcess(pid: 10, port: 8080))
    }
}
