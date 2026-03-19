import Foundation

/// A server configuration preset.
public struct ServerConfig: Equatable, Codable {
    public let name: String
    public let model: String
    public let maxTokens: Int
    public let extraArgs: [String]
    public let pythonPath: String

    public init(name: String, model: String, maxTokens: Int, extraArgs: [String], pythonPath: String) {
        self.name = name
        self.model = model
        self.maxTokens = maxTokens
        self.extraArgs = extraArgs
        self.pythonPath = pythonPath
    }
}
