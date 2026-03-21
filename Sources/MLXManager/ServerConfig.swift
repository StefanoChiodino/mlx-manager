import Foundation

/// Server type enum to choose between text-only and vision-language models.
public enum ServerType: String, Codable, CaseIterable {
    case mlxLM = "mlxLM"
    case mlxVLM = "mlxVLM"

    /// Human-readable name for UI display.
    public var descriptiveName: String {
        switch self {
        case .mlxLM:
            return "MLX-LM (text)"
        case .mlxVLM:
            return "MLX-VLM (vision)"
        }
    }

    /// Python module to import for the server.
    public var serverModule: String {
        serverEntryName
    }

    /// Python module entry point for `-m` argument.
    public var serverEntryName: String {
        switch self {
        case .mlxLM:
            return "mlx_lm.server"
        case .mlxVLM:
            return "mlx_vlm.server"
        }
    }
}

/// A server configuration preset.
public struct ServerConfig: Equatable, Codable {
    public let name: String
    public let model: String
    public let maxTokens: Int
    public let port: Int
    public let prefillStepSize: Int
    public let promptCacheSize: Int
    public let promptCacheBytes: Int
    public let trustRemoteCode: Bool
    public let enableThinking: Bool
    public let extraArgs: [String]
    public let serverType: ServerType
    public let pythonPath: String

    public init(
        name: String,
        model: String,
        maxTokens: Int,
        port: Int = 8080,
        prefillStepSize: Int = 4096,
        promptCacheSize: Int = 4,
        promptCacheBytes: Int = 10 * 1024 * 1024 * 1024,
        trustRemoteCode: Bool = false,
        enableThinking: Bool = false,
        extraArgs: [String] = [],
        serverType: ServerType = .mlxLM,
        pythonPath: String
    ) {
        self.name = name
        self.model = model
        self.maxTokens = maxTokens
        self.port = port
        self.prefillStepSize = prefillStepSize
        self.promptCacheSize = promptCacheSize
        self.promptCacheBytes = promptCacheBytes
        self.trustRemoteCode = trustRemoteCode
        self.enableThinking = enableThinking
        self.extraArgs = extraArgs
        self.serverType = serverType
        self.pythonPath = pythonPath
    }
}
