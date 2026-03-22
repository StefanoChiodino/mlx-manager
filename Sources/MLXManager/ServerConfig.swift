import Foundation

/// Server type enum to choose between text-only and vision-language models.
public enum ServerType: String, Codable, CaseIterable {
    case mlxLM = "mlxLM"
    case mlxVLM = "mlxVLM"

    public var descriptiveName: String {
        switch self {
        case .mlxLM:  return "MLX-LM (text)"
        case .mlxVLM: return "MLX-VLM (vision)"
        }
    }

    public var serverEntryName: String {
        switch self {
        case .mlxLM:  return "mlx_lm.server"
        case .mlxVLM: return "mlx_vlm.server"
        }
    }
}

/// A server configuration preset.
public struct ServerConfig: Equatable, Codable {
    // Shared fields
    public let name: String
    public let model: String
    public let port: Int
    public let prefillStepSize: Int
    public let trustRemoteCode: Bool
    public let extraArgs: [String]
    public let serverType: ServerType
    public let pythonPath: String

    // mlx-lm only
    public let maxTokens: Int
    public let promptCacheSize: Int
    public let promptCacheBytes: Int
    public let enableThinking: Bool

    // mlx-vlm only (omitted from CLI args when at default/zero)
    public let kvBits: Int            // 0 = disabled (omit flag)
    public let kvGroupSize: Int       // only emitted when kvBits > 0
    public let maxKvSize: Int         // 0 = disabled (omit flag)
    public let quantizedKvStart: Int  // only emitted when kvBits > 0

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
        kvBits: Int = 0,
        kvGroupSize: Int = 64,
        maxKvSize: Int = 0,
        quantizedKvStart: Int = 0,
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
        self.kvBits = kvBits
        self.kvGroupSize = kvGroupSize
        self.maxKvSize = maxKvSize
        self.quantizedKvStart = quantizedKvStart
        self.pythonPath = pythonPath
    }

    // MARK: - Decodable (custom to supply defaults for new VLM fields)

    enum CodingKeys: String, CodingKey {
        case name, model, port, prefillStepSize, trustRemoteCode, extraArgs, serverType, pythonPath
        case maxTokens, promptCacheSize, promptCacheBytes, enableThinking
        case kvBits, kvGroupSize, maxKvSize, quantizedKvStart
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name             = try c.decode(String.self,     forKey: .name)
        model            = try c.decode(String.self,     forKey: .model)
        maxTokens        = try c.decode(Int.self,        forKey: .maxTokens)
        port             = try c.decode(Int.self,        forKey: .port)
        prefillStepSize  = try c.decode(Int.self,        forKey: .prefillStepSize)
        promptCacheSize  = try c.decode(Int.self,        forKey: .promptCacheSize)
        promptCacheBytes = try c.decode(Int.self,        forKey: .promptCacheBytes)
        trustRemoteCode  = try c.decode(Bool.self,       forKey: .trustRemoteCode)
        enableThinking   = try c.decode(Bool.self,       forKey: .enableThinking)
        extraArgs        = try c.decode([String].self,   forKey: .extraArgs)
        serverType       = try c.decodeIfPresent(ServerType.self,  forKey: .serverType)       ?? .mlxLM
        pythonPath       = try c.decode(String.self,     forKey: .pythonPath)
        // VLM fields — fall back to defaults when absent (e.g. old serialised configs)
        kvBits           = try c.decodeIfPresent(Int.self, forKey: .kvBits)           ?? 0
        kvGroupSize      = try c.decodeIfPresent(Int.self, forKey: .kvGroupSize)      ?? 64
        maxKvSize        = try c.decodeIfPresent(Int.self, forKey: .maxKvSize)        ?? 0
        quantizedKvStart = try c.decodeIfPresent(Int.self, forKey: .quantizedKvStart) ?? 0
    }

    /// Returns a copy of this config with `pythonPath` tilde-expanded.
    /// All other fields are preserved exactly.
    public func withResolvedPythonPath() -> ServerConfig {
        let resolved = NSString(string: pythonPath).expandingTildeInPath
        guard resolved != pythonPath else { return self }
        return ServerConfig(
            name: name, model: model, maxTokens: maxTokens,
            port: port, prefillStepSize: prefillStepSize,
            promptCacheSize: promptCacheSize, promptCacheBytes: promptCacheBytes,
            trustRemoteCode: trustRemoteCode, enableThinking: enableThinking,
            extraArgs: extraArgs, serverType: serverType,
            kvBits: kvBits, kvGroupSize: kvGroupSize,
            maxKvSize: maxKvSize, quantizedKvStart: quantizedKvStart,
            pythonPath: resolved
        )
    }
}
