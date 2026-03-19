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
        let extraArgs: [String]?
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
            return ServerConfig(
                name: name,
                model: model,
                maxTokens: maxTokens,
                extraArgs: dto.extraArgs ?? []
            )
        }
    }
}
