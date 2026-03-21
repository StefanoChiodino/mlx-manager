import Testing
import Foundation
@testable import MLXManager

// MARK: - Test for multi-package installation

@Suite("EnvironmentBootstrapper - Multi-package installation")
struct EnvironmentBootstrapperMultiInstallTests {

    // MARK: T8 — installs both mlx-lm and mlx-vlm

    @Test("installs both mlx-lm and mlx-vlm packages")
    func test_install_installsBothMLXPackages() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy
        )

        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }

        let uvCalls = spy.calls.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "uv" }
        let pipCalls = uvCalls.filter { $0.arguments.first == "pip" }
        
        #expect(pipCalls.count >= 2, "Expected at least 2 'uv pip install' calls")
        
        let installedPackages = pipCalls.compactMap { pipCall -> String? in
            let installIndex = pipCall.arguments.firstIndex(where: { $0 == "install" })
            guard let installIndex = installIndex, pipCall.arguments.count > installIndex + 1
            else { return nil }
            return pipCall.arguments[installIndex + 1]
        }
        
        #expect(installedPackages.contains("mlx-lm"), "Expected 'mlx-lm' to be installed")
        #expect(installedPackages.contains("mlx-vlm"), "Expected 'mlx-vlm' to be installed")
    }

    // MARK: T9 — verifies installation order

    @Test("installs mlx-lm before mlx-vlm")
    func test_install_installsMLXLMBeforeMLXVLM() async throws {
        let spy = SpyCommandRunner()
        let bootstrapper = EnvironmentBootstrapper(
            uvLocator: UVLocator(fileExists: { path in path == UVLocator.candidatePaths[0] }),
            runner: spy
        )

        _ = await withCheckedContinuation { continuation in
            bootstrapper.onComplete = { _ in continuation.resume(returning: ()) }
            bootstrapper.install()
        }

        let uvCalls = spy.calls.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "uv" }
        let pipCalls = uvCalls.filter { $0.arguments.first == "pip" }
        
        let mlxLMIndex = pipCalls.firstIndex { $0.arguments.contains("mlx-lm") }
        let mlxVLMIndex = pipCalls.firstIndex { $0.arguments.contains("mlx-vlm") }
        
        #expect(mlxLMIndex != nil, "Expected mlx-lm installation")
        #expect(mlxVLMIndex != nil, "Expected mlx-vlm installation")
        #expect(mlxLMIndex! < mlxVLMIndex!, "Expected mlx-lm to be installed before mlx-vlm")
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
