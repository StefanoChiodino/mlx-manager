import Foundation

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
        self.pythonPath = pythonPath
    }
}
