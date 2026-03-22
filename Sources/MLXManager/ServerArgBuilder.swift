import Foundation

/// Assembles CLI arguments for a specific server backend.
public protocol ServerArgBuilder {
    func arguments(for config: ServerConfig) -> [String]
}

// MARK: - MLX-LM

/// Builds arguments for `mlx_lm.server`.
public struct MLXLmArgBuilder: ServerArgBuilder {
    public init() {}

    public func arguments(for config: ServerConfig) -> [String] {
        var args: [String] = [
            "-m", "mlx_lm.server",
            "--model", config.model,
            "--max-tokens", String(config.maxTokens),
            "--port", String(config.port),
            "--prefill-step-size", String(config.prefillStepSize),
            "--prompt-cache-size", String(config.promptCacheSize),
            "--prompt-cache-bytes", String(config.promptCacheBytes)
        ]
        if config.trustRemoteCode {
            args.append("--trust-remote-code")
        }
        // Always emitted — mlx-lm accepts this for all models.
        args.append("--chat-template-args")
        args.append("{\"enable_thinking\":\(config.enableThinking ? "true" : "false")}")
        args.append(contentsOf: config.extraArgs)
        return args
    }
}

// MARK: - MLX-VLM

/// Builds arguments for `mlx_vlm.server`.
public struct MLXVlmArgBuilder: ServerArgBuilder {
    public init() {}

    public func arguments(for config: ServerConfig) -> [String] {
        var args: [String] = [
            "-m", "mlx_vlm.server",
            "--model", config.model,
            "--port", String(config.port),
            "--prefill-step-size", String(config.prefillStepSize)
        ]
        if config.trustRemoteCode {
            args.append("--trust-remote-code")
        }
        // KV quantisation flags — only meaningful when kvBits > 0.
        if config.kvBits > 0 {
            args.append(contentsOf: ["--kv-bits", String(config.kvBits)])
            args.append(contentsOf: ["--kv-group-size", String(config.kvGroupSize)])
            args.append(contentsOf: ["--quantized-kv-start", String(config.quantizedKvStart)])
        }
        if config.maxKvSize > 0 {
            args.append(contentsOf: ["--max-kv-size", String(config.maxKvSize)])
        }
        args.append(contentsOf: config.extraArgs)
        return args
    }
}
