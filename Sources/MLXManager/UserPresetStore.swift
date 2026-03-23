import Foundation
import Yams

/// Loads and saves presets to/from a user-writable YAML file.
public enum UserPresetStore {

    /// Default location: ~/.config/mlx-manager/presets.yaml
    public static var defaultURL: URL {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mlx-manager")
        return config.appendingPathComponent("presets.yaml")
    }

    /// Load presets from the given URL. Throws if the file is missing or invalid.
    public static func load(from url: URL) throws -> [ServerConfig] {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try ConfigLoader.load(yaml: yaml)
    }

    /// Save presets to the given URL, creating intermediate directories as needed.
    public static func save(_ presets: [ServerConfig], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let yaml = try encodeYAML(presets)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private static func encodeYAML(_ presets: [ServerConfig]) throws -> String {
        struct PresetsFile: Encodable {
            let presets: [PresetDTO]
        }
        struct PresetDTO: Encodable {
            let name: String
            let model: String
            let maxTokens: Int
            let port: Int
            let prefillStepSize: Int
            let promptCacheSize: Int
            let promptCacheBytes: Int
            let trustRemoteCode: Bool
            let enableThinking: Bool
            let extraArgs: [String]
            let serverType: String
            let kvBits: Int
            let kvGroupSize: Int
            let maxKvSize: Int
            let quantizedKvStart: Int
            let pythonPath: String
        }
        let file = PresetsFile(presets: presets.map {
            PresetDTO(
                name: $0.name, model: $0.model, maxTokens: $0.maxTokens,
                port: $0.port, prefillStepSize: $0.prefillStepSize,
                promptCacheSize: $0.promptCacheSize, promptCacheBytes: $0.promptCacheBytes,
                trustRemoteCode: $0.trustRemoteCode, enableThinking: $0.enableThinking,
                extraArgs: $0.extraArgs, serverType: $0.serverType.rawValue,
                kvBits: $0.kvBits, kvGroupSize: $0.kvGroupSize,
                maxKvSize: $0.maxKvSize, quantizedKvStart: $0.quantizedKvStart,
                pythonPath: $0.pythonPath
            )
        })
        return try YAMLEncoder().encode(file)
    }
}
