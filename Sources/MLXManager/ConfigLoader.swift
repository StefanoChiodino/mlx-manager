import Foundation
import Yams

/// Errors from config loading.
public enum ConfigError: Error, Equatable {
    case invalidYAML
    case missingField(String)
}

/// Loads server configuration presets from YAML.
public enum ConfigLoader {

    // MARK: - Codable DTOs

    private struct PresetsFile: Decodable {
        let presets: [PresetDTO]
    }

    private struct PresetDTO: Decodable {
        let name: String?
        let model: String?
        let maxTokens: Int?
        let port: Int?
        let prefillStepSize: Int?
        let promptCacheSize: Int?
        let promptCacheBytes: Int?
        let trustRemoteCode: Bool?
        let enableThinking: Bool?
        let extraArgs: [String]?
        let serverType: ServerType?
        let kvBits: Int?
        let kvGroupSize: Int?
        let maxKvSize: Int?
        let quantizedKvStart: Int?
        let pythonPath: String?
    }

    // MARK: - Public API

    /// Parse a YAML string into an array of ServerConfig presets.
    public static func load(yaml: String) throws -> [ServerConfig] {
        let file: PresetsFile
        do {
            let decoder = YAMLDecoder()
            file = try decoder.decode(PresetsFile.self, from: yaml)
        } catch {
            throw ConfigError.invalidYAML
        }

        return try file.presets.map { dto in
            guard let name = dto.name else { throw ConfigError.missingField("name") }
            guard let model = dto.model else { throw ConfigError.missingField("model") }
            guard let maxTokens = dto.maxTokens else { throw ConfigError.missingField("maxTokens") }
            guard let pythonPath = dto.pythonPath else { throw ConfigError.missingField("pythonPath") }
            return ServerConfig(
                name: name,
                model: model,
                maxTokens: maxTokens,
                port: dto.port ?? 8080,
                prefillStepSize: dto.prefillStepSize ?? 4096,
                promptCacheSize: dto.promptCacheSize ?? 4,
                promptCacheBytes: dto.promptCacheBytes ?? 10 * 1024 * 1024 * 1024,
                trustRemoteCode: dto.trustRemoteCode ?? false,
                enableThinking: dto.enableThinking ?? false,
                extraArgs: dto.extraArgs ?? [],
                serverType: dto.serverType ?? .mlxLM,
                kvBits: dto.kvBits ?? 0,
                kvGroupSize: dto.kvGroupSize ?? 64,
                maxKvSize: dto.maxKvSize ?? 0,
                quantizedKvStart: dto.quantizedKvStart ?? 0,
                pythonPath: pythonPath
            )
        }
    }
}
