import Testing
import XCTest
import Foundation
@testable import MLXManager

// MARK: - Test double

final class SpyCommandRunner: CommandRunner {
    struct Call: Equatable {
        let command: String
        let arguments: [String]
    }
    var calls: [Call] = []
    var exitCodeMap: [String: Int32] = [:]   // keyed on command basename

    func run(command: String, arguments: [String], onOutput: @escaping (String) -> Void) -> Int32 {
        calls.append(Call(command: command, arguments: arguments))
        let key = (command as NSString).lastPathComponent
        return exitCodeMap[key] ?? 0
    }
}

// MARK: - Tests

@Suite("EnvironmentBootstrapper")
struct EnvironmentBootstrapperTests {

    // MARK: T4 — uses uv venv + uv pip install when uv is found

    @Test("uses 'uv venv' and 'uv pip install' when uv is present")
    func test_install_whenUVFound_usesUVCommands() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy,
            uvInstallCommand: nil   // should not be called
        )

        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }

        let uvCalls = spy.calls.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "uv" }
        let venvCall = uvCalls.first(where: { $0.arguments.first == "venv" })
        let pipCall  = uvCalls.first(where: { $0.arguments.first == "pip" })
        #expect(venvCall != nil, "expected 'uv venv' call")
        #expect(pipCall != nil,  "expected 'uv pip' call")
        if let pip = pipCall {
            #expect(pip.arguments.contains("mlx-lm"))
        }
    }

    // MARK: T5 — skips uv install when uv is already found

    @Test("skips uv installer script when uv is already present")
    func test_install_whenUVFound_skipsInstallStep() async throws {
        let spy = SpyCommandRunner()
        var installerRan = false
        let bootstrapper = EnvironmentBootstrapper(
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy,
            uvInstallCommand: { installerRan = true; return true }
        )

        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }

        #expect(installerRan == false)
    }

    // MARK: T6 — runs uv install when uv is absent

    @Test("runs uv installer script when uv is not found")
    func test_install_whenUVMissing_runsInstallStep() async throws {
        let spy = SpyCommandRunner()
        var installerRan = false
        let bootstrapper = EnvironmentBootstrapper(
            uvLocator: UVLocator(fileExists: { _ in false }),
            runner: spy,
            uvInstallCommand: {
                installerRan = true
                return true   // simulate successful install
            }
        )

        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }

        #expect(installerRan == true)
    }

    // MARK: T7 — onComplete(false) when uv install fails

    @Test("calls onComplete(false) when uv installer fails")
    func test_install_whenUVInstallFails_completesWithFailure() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            uvLocator: UVLocator(fileExists: { _ in false }),
            runner: spy,
            uvInstallCommand: { return false }
        )

        let success = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { continuation.resume(returning: $0) }
            bootstrapper.install()
        }

        #expect(success == false)
    }

    // MARK: T8 — each backend installs exactly one package

    @Test("default (mlxLM) bootstrapper installs exactly one pip package: mlx-lm")
    func test_install_lmBootstrapper_installsExactlyOnePackage() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            backend: .mlxLM,
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy,
            uvInstallCommand: nil
        )

        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }

        let pipCalls = spy.calls.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "uv" }
            .filter { $0.arguments.first == "pip" && $0.arguments.contains("install") }

        // New design: one pip install per bootstrapper instance
        #expect(pipCalls.count == 1, "expected exactly 1 pip install call for mlxLM backend")
        #expect(pipCalls.first?.arguments.contains("mlx-lm") == true, "expected pip install mlx-lm")
    }
}

// MARK: - Backend-aware tests (XCTest)

class EnvironmentBootstrapperBackendTests: XCTestCase {

    func test_pythonPath_lm() {
        let path = EnvironmentBootstrapper.pythonPath(for: .mlxLM)
        XCTAssertTrue(path.contains(".mlx-manager/venv/bin/python"))
        XCTAssertFalse(path.contains("venv-vlm"))
    }

    func test_pythonPath_vlm() {
        let path = EnvironmentBootstrapper.pythonPath(for: .mlxVLM)
        XCTAssertTrue(path.contains(".mlx-manager/venv-vlm/bin/python"))
    }

    func test_venvPath_lm() {
        let path = EnvironmentBootstrapper.venvPath(for: .mlxLM)
        XCTAssertTrue(path.contains(".mlx-manager/venv"))
        XCTAssertFalse(path.contains("venv-vlm"))
    }

    func test_venvPath_vlm() {
        let path = EnvironmentBootstrapper.venvPath(for: .mlxVLM)
        XCTAssertTrue(path.contains(".mlx-manager/venv-vlm"))
    }

    func test_install_lm_usesMLXLmPackage() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            backend: .mlxLM,
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy
        )
        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }
        let allPipCalls = spy.calls.filter { $0.arguments.first == "pip" }
        XCTAssertTrue(allPipCalls.contains(where: { $0.arguments.contains("mlx-lm") }), "expected pip install mlx-lm")
        XCTAssertFalse(allPipCalls.contains(where: { $0.arguments.contains("mlx-vlm") }), "LM bootstrapper must not install mlx-vlm")
    }

    func test_install_vlm_usesMLXVlmPackage() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            backend: .mlxVLM,
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy
        )
        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }
        let allPipCalls = spy.calls.filter { $0.arguments.first == "pip" }
        XCTAssertTrue(allPipCalls.contains(where: { $0.arguments.contains("mlx-vlm") }), "expected pip install mlx-vlm")
        XCTAssertFalse(allPipCalls.contains(where: { $0.arguments.contains("mlx-lm") }), "VLM bootstrapper must not install mlx-lm")
    }
}
