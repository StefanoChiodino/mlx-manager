import Foundation

/// User-configurable app settings, persisted to ~/.config/mlx-manager/settings.json.
public struct AppSettings: Codable, Equatable {
    public var ramGraphEnabled: Bool = false
    public var ramPollInterval: Int = 5   // seconds: 2, 5, or 10
    public var startAtLogin: Bool = false
    public var logPath: String = "~/repos/mlx/Logs/server.log"
    /// Treat prompt processing as complete at this percentage (0 = disabled). Default 99.
    public var progressCompletionThreshold: Int = 99

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case ramGraphEnabled
        case ramPollInterval
        case startAtLogin
        case logPath
        case progressCompletionThreshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ramGraphEnabled = try container.decode(Bool.self, forKey: .ramGraphEnabled)
        ramPollInterval = try container.decode(Int.self, forKey: .ramPollInterval)
        startAtLogin = try container.decode(Bool.self, forKey: .startAtLogin)
        logPath = try container.decode(String.self, forKey: .logPath)
        progressCompletionThreshold = try container.decodeIfPresent(Int.self, forKey: .progressCompletionThreshold) ?? 99
    }
}
