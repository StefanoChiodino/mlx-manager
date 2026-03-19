import Foundation

/// User-configurable app settings, persisted to ~/.config/mlx-manager/settings.json.
public struct AppSettings: Codable, Equatable {
    public var ramGraphEnabled: Bool = false
    public var ramPollInterval: Int = 5   // seconds: 2, 5, or 10

    public init() {}
}
