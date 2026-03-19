import Foundation

/// Locates the `uv` binary on the current machine.
public struct UVLocator {

    /// Ordered list of paths to check for a `uv` binary.
    public static let candidatePaths: [String] = [
        NSString("~/.local/bin/uv").expandingTildeInPath,
        "/opt/homebrew/bin/uv",
    ]

    public let fileExists: (String) -> Bool

    public init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        self.fileExists = fileExists
    }

    /// Returns the first candidate path at which `uv` exists, or `nil` if none found.
    public func locate() -> String? {
        Self.candidatePaths.first { fileExists($0) }
    }
}
