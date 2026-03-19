import Foundation

/// A server configuration preset.
public struct ServerConfig: Equatable {
    public let name: String
    public let model: String
    public let maxTokens: Int
    public let extraArgs: [String]
}
