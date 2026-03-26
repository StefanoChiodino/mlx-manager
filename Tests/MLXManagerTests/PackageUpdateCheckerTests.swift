import XCTest
@testable import MLXManager

final class SpyRunner: CommandRunner {
    struct Call: Equatable {
        let command: String
        let arguments: [String]
    }
    var calls: [Call] = []
    var outputByArgPrefix: [String: String] = [:]
    var exitCode: Int32 = 0

    func run(command: String, arguments: [String], onOutput: @escaping (String) -> Void) -> Int32 {
        calls.append(Call(command: command, arguments: arguments))
        if let prefix = arguments.first, let output = outputByArgPrefix[prefix] {
            onOutput(output)
        }
        return exitCode
    }
}

final class PackageUpdateCheckerTests: XCTestCase {

    func test_parseOutdated_withUpdates_returnsPackageInfo() {
        let output = """
        Package    Version    Latest    Type
        mlx-lm     0.21.0     0.22.1    sdist
        """
        let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.currentVersion, "0.21.0")
        XCTAssertEqual(result?.latestVersion, "0.22.1")
    }

    func test_parseOutdated_noUpdates_returnsNil() {
        let output = """
        Package    Version    Latest    Type
        """
        let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
        XCTAssertNil(result)
    }

    func test_parseOutdated_emptyOutput_returnsNil() {
        let result = PackageUpdateChecker.parseOutdated(output: "", packageName: "mlx-lm")
        XCTAssertNil(result)
    }

    func test_parseOutdated_differentPackageOutdated_returnsNil() {
        let output = """
        Package    Version    Latest    Type
        numpy      1.25.0     1.26.0    sdist
        """
        let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
        XCTAssertNil(result)
    }

    func test_checkForUpdates_runsOutdatedCommandForBothVenvs() {
        let spy = SpyRunner()
        let checker = PackageUpdateChecker(uvPath: "/usr/local/bin/uv", runner: spy)

        checker.checkForUpdates { _ in }

        let outdatedCalls = spy.calls.filter { $0.arguments.contains("--outdated") }
        XCTAssertEqual(outdatedCalls.count, 2)

        let pythonPaths = outdatedCalls.compactMap { call -> String? in
            guard let idx = call.arguments.firstIndex(of: "--python"),
                  idx + 1 < call.arguments.count else { return nil }
            return call.arguments[idx + 1]
        }
        XCTAssertTrue(pythonPaths.contains(EnvironmentBootstrapper.pythonPath(for: .mlxLM)))
        XCTAssertTrue(pythonPaths.contains(EnvironmentBootstrapper.pythonPath(for: .mlxVLM)))
    }

    func test_upgrade_runsInstallUpgradeForBothVenvs() {
        let spy = SpyRunner()
        let checker = PackageUpdateChecker(uvPath: "/usr/local/bin/uv", runner: spy)

        checker.upgrade { _ in }

        let upgradeCalls = spy.calls.filter { $0.arguments.contains("--upgrade") }
        XCTAssertEqual(upgradeCalls.count, 2)

        let packages = upgradeCalls.compactMap { call -> String? in
            return call.arguments.first(where: { $0 == "mlx-lm" || $0 == "mlx-vlm" })
        }
        XCTAssertTrue(packages.contains("mlx-lm"))
        XCTAssertTrue(packages.contains("mlx-vlm"))
    }

    func test_upgrade_returnsFalseOnFailure() {
        let spy = SpyRunner()
        spy.exitCode = 1
        let checker = PackageUpdateChecker(uvPath: "/usr/local/bin/uv", runner: spy)

        var result = true
        checker.upgrade { result = $0 }

        XCTAssertFalse(result)
    }
}
