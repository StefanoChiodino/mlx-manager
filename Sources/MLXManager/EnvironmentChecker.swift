import Foundation

/// Checks whether the managed Python environment is ready to use.
public struct EnvironmentChecker {

    public let fileExists: (String) -> Bool

    public init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        self.fileExists = fileExists
    }

    /// Returns `true` when the Python binary at `pythonPath` exists on disk.
    public func isReady(pythonPath: String) -> Bool {
        fileExists(pythonPath)
    }
}
