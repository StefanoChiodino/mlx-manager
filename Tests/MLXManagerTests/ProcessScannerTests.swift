import Testing
import XCTest
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
        #expect(scanner.findServer(backend: .mlxLM) == nil)
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
        #expect(scanner.findServer(backend: .mlxLM) == nil)
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
        #expect(scanner.findServer(backend: .mlxLM) == DiscoveredProcess(pid: 42, port: 8080))
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
        #expect(scanner.findServer(backend: .mlxLM) == DiscoveredProcess(pid: 7, port: 8080))
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
        #expect(scanner.findServer(backend: .mlxLM) == DiscoveredProcess(pid: 9, port: 8080))
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
        #expect(scanner.findServer(backend: .mlxLM)?.port == 9000)
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
        #expect(scanner.findServer(backend: .mlxLM)?.port == 8080)
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
        #expect(scanner.findServer(backend: .mlxLM)?.port == 8080)
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
        #expect(scanner.findServer(backend: .mlxLM)?.port == 8080)
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
        #expect(scanner.findServer(backend: .mlxLM) == DiscoveredProcess(pid: 2, port: 8080))
    }

    // T8b
    @Test("argv contains path ending in /mlx_lm.server (venv bin script) — returns DiscoveredProcess")
    func test_findMLXServer_venvBinScriptInArgv_returnsDiscoveredProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([11]),
            argvReader: StubProcessArgvReader([
                11: ["/opt/homebrew/.../Python", "/Users/user/repos/mlx/venv/bin/mlx_lm.server", "--port", "8080"]
            ])
        )
        #expect(scanner.findServer(backend: .mlxLM) == DiscoveredProcess(pid: 11, port: 8080))
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
        #expect(scanner.findServer(backend: .mlxLM) == DiscoveredProcess(pid: 10, port: 8080))
    }
}

// MARK: - ProcessScannerBackendTests (XCTest)

class ProcessScannerBackendTests: XCTestCase {

    // VLM detection tests

    func test_findServer_vlm_moduleFlag() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([10]),
            argvReader: StubProcessArgvReader([
                10: ["/venv/bin/python", "-m", "mlx_vlm.server", "--port", "8082"]
            ])
        )
        XCTAssertEqual(scanner.findServer(backend: .mlxVLM), DiscoveredProcess(pid: 10, port: 8082))
    }

    func test_findServer_vlm_bareElement() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([11]),
            argvReader: StubProcessArgvReader([
                11: ["mlx_vlm.server", "--port", "8082"]
            ])
        )
        XCTAssertEqual(scanner.findServer(backend: .mlxVLM), DiscoveredProcess(pid: 11, port: 8082))
    }

    func test_findServer_vlm_scriptPath() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([12]),
            argvReader: StubProcessArgvReader([
                12: ["/python3", "/site-packages/mlx_vlm/server.py", "--port", "8082"]
            ])
        )
        XCTAssertEqual(scanner.findServer(backend: .mlxVLM), DiscoveredProcess(pid: 12, port: 8082))
    }

    func test_findServer_vlm_venvBinScript() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([13]),
            argvReader: StubProcessArgvReader([
                13: ["/python3", "/venv-vlm/bin/mlx_vlm.server", "--port", "8082"]
            ])
        )
        XCTAssertEqual(scanner.findServer(backend: .mlxVLM), DiscoveredProcess(pid: 13, port: 8082))
    }

    // Cross-contamination tests

    func test_findServer_lm_doesNotMatchVLMProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([20]),
            argvReader: StubProcessArgvReader([
                20: ["/python3", "-m", "mlx_vlm.server", "--port", "8082"]
            ])
        )
        XCTAssertNil(scanner.findServer(backend: .mlxLM))
    }

    func test_findServer_vlm_doesNotMatchLMProcess() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([21]),
            argvReader: StubProcessArgvReader([
                21: ["/python3", "-m", "mlx_lm.server", "--port", "8081"]
            ])
        )
        XCTAssertNil(scanner.findServer(backend: .mlxVLM))
    }

    // findAnyServer tests

    func test_findAnyServer_lmRunning_returnsIt() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([30]),
            argvReader: StubProcessArgvReader([
                30: ["/venv/bin/python", "-m", "mlx_lm.server", "--port", "8080"]
            ])
        )
        XCTAssertEqual(scanner.findAnyServer(), DiscoveredProcess(pid: 30, port: 8080))
    }

    func test_findAnyServer_vlmRunning_returnsIt() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([31]),
            argvReader: StubProcessArgvReader([
                31: ["/venv/bin/python", "-m", "mlx_vlm.server", "--port", "8082"]
            ])
        )
        XCTAssertEqual(scanner.findAnyServer(), DiscoveredProcess(pid: 31, port: 8082))
    }

    func test_findAnyServer_nothingRunning_returnsNil() {
        let scanner = ProcessScanner(
            pidLister: StubPIDLister([32]),
            argvReader: StubProcessArgvReader([
                32: ["/bin/bash", "-c", "echo hello"]
            ])
        )
        XCTAssertNil(scanner.findAnyServer())
    }
}
