import Testing
import Foundation
@testable import MLXManager

// MARK: - Test for per-backend installation

@Suite("EnvironmentBootstrapper - Per-backend installation")
struct EnvironmentBootstrapperMultiInstallTests {

    // MARK: T8 — mlxLM bootstrapper installs only mlx-lm

    @Test("mlxLM bootstrapper installs mlx-lm, not mlx-vlm")
    func test_install_lmBootstrapper_installsOnlyMLXLm() async throws {
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

        let uvCalls = spy.calls.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "uv" }
        let pipCalls = uvCalls.filter { $0.arguments.first == "pip" }

        #expect(pipCalls.count == 1, "Expected exactly 1 'uv pip install' call for mlxLM backend")

        let installedPackages = pipCalls.compactMap { pipCall -> String? in
            let installIndex = pipCall.arguments.firstIndex(where: { $0 == "install" })
            guard let installIndex = installIndex, pipCall.arguments.count > installIndex + 1
            else { return nil }
            return pipCall.arguments[installIndex + 1]
        }

        #expect(installedPackages.contains("mlx-lm"), "Expected 'mlx-lm' to be installed")
        #expect(!installedPackages.contains("mlx-vlm"), "Expected 'mlx-vlm' NOT to be installed by mlxLM backend")
    }

    // MARK: T9 — mlxVLM bootstrapper installs only mlx-vlm

    @Test("mlxVLM bootstrapper installs mlx-vlm, not mlx-lm")
    func test_install_vlmBootstrapper_installsOnlyMLXVlm() async throws {
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

        let uvCalls = spy.calls.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "uv" }
        let pipCalls = uvCalls.filter { $0.arguments.first == "pip" }

        #expect(pipCalls.count == 1, "Expected exactly 1 'uv pip install' call for mlxVLM backend")

        let installedPackages = pipCalls.compactMap { pipCall -> String? in
            let installIndex = pipCall.arguments.firstIndex(where: { $0 == "install" })
            guard let installIndex = installIndex, pipCall.arguments.count > installIndex + 1
            else { return nil }
            return pipCall.arguments[installIndex + 1]
        }

        #expect(installedPackages.contains("mlx-vlm"), "Expected 'mlx-vlm' to be installed")
        #expect(!installedPackages.contains("mlx-lm"), "Expected 'mlx-lm' NOT to be installed by mlxVLM backend")
    }

    // MARK: - Test doubles

    final class SpyCommandRunner: CommandRunner {
        struct Call: Equatable {
            let command: String
            let arguments: [String]
        }
        var calls: [Call] = []
        var exitCodeMap: [String: Int32] = [:]

        func run(command: String, arguments: [String], onOutput: @escaping (String) -> Void) -> Int32 {
            calls.append(Call(command: command, arguments: arguments))
            let key = (command as NSString).lastPathComponent
            return exitCodeMap[key] ?? 0
        }
    }
}
