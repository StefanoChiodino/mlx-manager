import Foundation

/// Result of checking a single package for updates.
public struct OutdatedPackage: Equatable {
    public let name: String
    public let currentVersion: String
    public let latestVersion: String
}

/// Checks for and applies mlx-lm/mlx-vlm package updates using `uv`.
public struct PackageUpdateChecker {

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
}
