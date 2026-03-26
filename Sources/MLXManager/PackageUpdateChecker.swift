import Foundation

/// Result of checking a single package for updates.
public struct OutdatedPackage: Equatable {
    public let name: String
    public let currentVersion: String
    public let latestVersion: String
}

/// Checks for and applies mlx-lm/mlx-vlm package updates using `uv`.
public struct PackageUpdateChecker {

    private let uvPath: String
    private let runner: CommandRunner

    public init(uvPath: String, runner: CommandRunner) {
        self.uvPath = uvPath
        self.runner = runner
    }

    /// Result of checking both venvs for updates.
    public struct CheckResult: Equatable {
        public let mlxLM: OutdatedPackage?
        public let mlxVLM: OutdatedPackage?

        public var hasUpdates: Bool { mlxLM != nil || mlxVLM != nil }
    }

    /// Parse `uv pip list --outdated` output for a specific package.
    /// Returns nil if the package is not in the outdated list.
    public static func parseOutdated(output: String, packageName: String) -> OutdatedPackage? {
        for line in output.components(separatedBy: .newlines) {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 3 else { continue }
            let name = String(columns[0])
            if name.lowercased() == packageName.lowercased() {
                return OutdatedPackage(
                    name: name,
                    currentVersion: String(columns[1]),
                    latestVersion: String(columns[2])
                )
            }
        }
        return nil
    }

    /// Check both venvs for outdated packages. Calls completion on the calling thread.
    public func checkForUpdates(completion: @escaping (CheckResult) -> Void) {
        let lmPython = EnvironmentBootstrapper.pythonPath(for: .mlxLM)
        let vlmPython = EnvironmentBootstrapper.pythonPath(for: .mlxVLM)

        let lmOutput = runList(python: lmPython)
        let vlmOutput = runList(python: vlmPython)

        let result = CheckResult(
            mlxLM: Self.parseOutdated(output: lmOutput, packageName: "mlx-lm"),
            mlxVLM: Self.parseOutdated(output: vlmOutput, packageName: "mlx-vlm")
        )
        completion(result)
    }

    private func runList(python: String) -> String {
        var output = ""
        _ = runner.run(
            command: uvPath,
            arguments: ["pip", "list", "--outdated", "--python", python],
            onOutput: { output += $0 }
        )
        return output
    }

    /// Upgrade both venvs. Returns true if both succeed.
    public func upgrade(completion: @escaping (Bool) -> Void) {
        let lmPython = EnvironmentBootstrapper.pythonPath(for: .mlxLM)
        let vlmPython = EnvironmentBootstrapper.pythonPath(for: .mlxVLM)

        let lmOK = runUpgrade(package: "mlx-lm", python: lmPython)
        let vlmOK = runUpgrade(package: "mlx-vlm", python: vlmPython)

        completion(lmOK && vlmOK)
    }

    private func runUpgrade(package: String, python: String) -> Bool {
        let code = runner.run(
            command: uvPath,
            arguments: ["pip", "install", "--upgrade", package, "--python", python],
            onOutput: { _ in }
        )
        return code == 0
    }
}
