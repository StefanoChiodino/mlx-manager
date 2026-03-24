import Foundation

/// User-configurable app settings, persisted to ~/.config/mlx-manager/settings.json.
public struct AppSettings: Codable, Equatable {
    public var ramGraphEnabled: Bool = false
    public var ramPollInterval: Int = 5   // seconds: 2, 5, or 10
    public var startAtLogin: Bool = false
    public var logPath: String = "~/repos/mlx/Logs/server.log"
    /// Treat prompt processing as complete at this percentage (0 = disabled). Default 0.
    public var progressCompletionThreshold: Int = 0
    /// Show the last server log line in the menu bar status item. Default false.
    public var showLastLogLine: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case ramGraphEnabled
        case ramPollInterval
        case startAtLogin
        case logPath
        case progressCompletionThreshold
        case showLastLogLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ramGraphEnabled = try container.decode(Bool.self, forKey: .ramGraphEnabled)
        ramPollInterval = try container.decode(Int.self, forKey: .ramPollInterval)
        startAtLogin = try container.decode(Bool.self, forKey: .startAtLogin)
        logPath = try container.decode(String.self, forKey: .logPath)
        progressCompletionThreshold = try container.decodeIfPresent(Int.self, forKey: .progressCompletionThreshold) ?? 0
        showLastLogLine = try container.decodeIfPresent(Bool.self, forKey: .showLastLogLine) ?? false
    }
}
