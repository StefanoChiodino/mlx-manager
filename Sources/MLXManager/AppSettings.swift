import Foundation

/// How the status bar icon represents request progress.
public enum ProgressStyle: String, Codable, Equatable {
    case bar   // ▓▓▓░░░░░░░ 32%
    case pie   // ◑
}

/// User-configurable app settings, persisted to ~/.config/mlx-manager/settings.json.
public struct AppSettings: Codable, Equatable {
    public var progressStyle: ProgressStyle = .bar
    public var ramGraphEnabled: Bool = false
    public var ramPollInterval: Int = 5   // seconds: 2, 5, or 10

    public init() {}
}
