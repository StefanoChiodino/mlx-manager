import Foundation

/// User-configurable app settings, persisted to ~/.config/mlx-manager/settings.json.
public struct AppSettings: Codable, Equatable {
    public var ramGraphEnabled: Bool = false
    public var ramPollInterval: Int = 5   // seconds: 2, 5, or 10
    public var startAtLogin: Bool = false
    public var logPath: String = "~/repos/mlx/Logs/server.log"
    /// Port used by the backend server in direct mode, and by the hidden backend when the proxy is enabled.
    public var serverPort: Int = 8080
    /// Public port exposed by the optional managed gateway. When it matches `serverPort`, the backend falls back to a hidden offset port.
    public var managedGatewayPort: Int = 8080
    /// Treat prompt processing as complete at this percentage (0 = disabled). Default 0.
    public var progressCompletionThreshold: Int = 0
    /// Show the last server log line in the menu bar status item. Default false.
    public var showLastLogLine: Bool = false
    /// Route requests through MLX Manager so clients can use a stable port and `default` model alias.
    public var managedGatewayEnabled: Bool = false
    /// Optional global Python override. When empty, the managed backend-specific Python is used.
    public var pythonPathOverride: String = ""
    /// Show prefill speed (tok/s) in the menu bar status item. Default false.
    public var showPrefillTPS: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case ramGraphEnabled
        case ramPollInterval
        case startAtLogin
        case logPath
        case serverPort
        case managedGatewayPort
        case progressCompletionThreshold
        case showLastLogLine
        case managedGatewayEnabled
        case pythonPathOverride
        case showPrefillTPS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ramGraphEnabled = try container.decode(Bool.self, forKey: .ramGraphEnabled)
        ramPollInterval = try container.decode(Int.self, forKey: .ramPollInterval)
        startAtLogin = try container.decode(Bool.self, forKey: .startAtLogin)
        logPath = try container.decode(String.self, forKey: .logPath)
        serverPort = try container.decodeIfPresent(Int.self, forKey: .serverPort) ?? 8080
        managedGatewayPort = try container.decodeIfPresent(Int.self, forKey: .managedGatewayPort) ?? 8080
        progressCompletionThreshold = try container.decodeIfPresent(Int.self, forKey: .progressCompletionThreshold) ?? 0
        showLastLogLine = try container.decodeIfPresent(Bool.self, forKey: .showLastLogLine) ?? false
        managedGatewayEnabled = try container.decodeIfPresent(Bool.self, forKey: .managedGatewayEnabled) ?? false
        pythonPathOverride = try container.decodeIfPresent(String.self, forKey: .pythonPathOverride) ?? ""
        showPrefillTPS = try container.decodeIfPresent(Bool.self, forKey: .showPrefillTPS) ?? false
    }

    /// Hidden backend port used while the managed gateway owns the public port.
    public var managedGatewayBackendPort: Int {
        if managedGatewayPort == serverPort {
            return serverPort + ManagedGatewayRouting.backendPortOffset
        }
        return serverPort
    }

    public var hasPythonPathOverride: Bool {
        !pythonPathOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func resolvedPythonPath(for config: ServerConfig) -> String {
        resolvedPythonPath(for: config.serverType, fallback: config.pythonPath)
    }

    public func resolvedPythonPath(for serverType: ServerType, fallback: String? = nil) -> String {
        let trimmedOverride = pythonPathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverride.isEmpty {
            return NSString(string: trimmedOverride).expandingTildeInPath
        }
        let path = fallback ?? ServerConfig.defaultPythonPath(for: serverType)
        return NSString(string: path).expandingTildeInPath
    }
}
