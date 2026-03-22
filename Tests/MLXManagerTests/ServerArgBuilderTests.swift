import XCTest
@testable import MLXManager

// MARK: - MLXLmArgBuilder

class MLXLmArgBuilderTests: XCTestCase {

    func makeConfig(
        model: String = "mlx-community/Qwen3-4bit",
        maxTokens: Int = 40960,
        port: Int = 8081,
        prefillStepSize: Int = 4096,
        promptCacheSize: Int = 4,
        promptCacheBytes: Int = 10 * 1024 * 1024 * 1024,
        trustRemoteCode: Bool = false,
        enableThinking: Bool = false,
        extraArgs: [String] = [],
        pythonPath: String = "/venv/bin/python"
    ) -> ServerConfig {
        ServerConfig(
            name: "test", model: model, maxTokens: maxTokens,
            port: port, prefillStepSize: prefillStepSize,
            promptCacheSize: promptCacheSize, promptCacheBytes: promptCacheBytes,
            trustRemoteCode: trustRemoteCode, enableThinking: enableThinking,
            extraArgs: extraArgs, serverType: .mlxLM, pythonPath: pythonPath
        )
    }

    func test_lm_coreArgs() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig())
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("mlx_lm.server"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("--max-tokens"))
        XCTAssertTrue(args.contains("--port"))
        XCTAssertTrue(args.contains("--prefill-step-size"))
        XCTAssertTrue(args.contains("--prompt-cache-size"))
        XCTAssertTrue(args.contains("--prompt-cache-bytes"))
    }

    func test_lm_chatTemplateArgs_false() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(enableThinking: false))
        XCTAssertTrue(args.contains("--chat-template-args"))
        let idx = args.firstIndex(of: "--chat-template-args")!
        XCTAssertEqual(args[idx + 1], "{\"enable_thinking\":false}")
    }

    func test_lm_chatTemplateArgs_true() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(enableThinking: true))
        let idx = args.firstIndex(of: "--chat-template-args")!
        XCTAssertEqual(args[idx + 1], "{\"enable_thinking\":true}")
    }

    func test_lm_trustRemoteCode_omittedWhenFalse() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(trustRemoteCode: false))
        XCTAssertFalse(args.contains("--trust-remote-code"))
    }

    func test_lm_trustRemoteCode_includedWhenTrue() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(trustRemoteCode: true))
        XCTAssertTrue(args.contains("--trust-remote-code"))
    }

    func test_lm_extraArgs() {
        let args = MLXLmArgBuilder().arguments(for: makeConfig(extraArgs: ["--foo", "bar"]))
        XCTAssertEqual(Array(args.suffix(2)), ["--foo", "bar"])
    }

    func test_lm_fullArgList() {
        let config = ServerConfig(
            name: "t", model: "mlx-community/Qwen3-4bit", maxTokens: 40960,
            port: 8081, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10_737_418_240,
            trustRemoteCode: true, enableThinking: false,
            extraArgs: [], serverType: .mlxLM,
            pythonPath: "/venv/bin/python"
        )
        let args = MLXLmArgBuilder().arguments(for: config)
        XCTAssertEqual(args, [
            "-m", "mlx_lm.server",
            "--model", "mlx-community/Qwen3-4bit",
            "--max-tokens", "40960",
            "--port", "8081",
            "--prefill-step-size", "4096",
            "--prompt-cache-size", "4",
            "--prompt-cache-bytes", "10737418240",
            "--trust-remote-code",
            "--chat-template-args", "{\"enable_thinking\":false}"
        ])
    }
}

// MARK: - MLXVlmArgBuilder

class MLXVlmArgBuilderTests: XCTestCase {

    func makeConfig(
        model: String = "mlx-community/Qwen2.5-VL-7B-4bit",
        port: Int = 8082,
        prefillStepSize: Int = 512,
        trustRemoteCode: Bool = false,
        extraArgs: [String] = [],
        kvBits: Int = 0,
        kvGroupSize: Int = 64,
        maxKvSize: Int = 0,
        quantizedKvStart: Int = 0
    ) -> ServerConfig {
        ServerConfig(
            name: "vlm", model: model, maxTokens: 0,
            port: port, prefillStepSize: prefillStepSize,
            trustRemoteCode: trustRemoteCode,
            extraArgs: extraArgs, serverType: .mlxVLM,
            kvBits: kvBits, kvGroupSize: kvGroupSize,
            maxKvSize: maxKvSize, quantizedKvStart: quantizedKvStart,
            pythonPath: "/venv-vlm/bin/python"
        )
    }

    func test_vlm_coreArgs() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig())
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("mlx_vlm.server"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("--port"))
        XCTAssertTrue(args.contains("--prefill-step-size"))
    }

    func test_vlm_noLMOnlyArgs() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig())
        XCTAssertFalse(args.contains("--max-tokens"))
        XCTAssertFalse(args.contains("--prompt-cache-size"))
        XCTAssertFalse(args.contains("--prompt-cache-bytes"))
        XCTAssertFalse(args.contains("--chat-template-args"))
    }

    func test_vlm_kvBitsZero_omitsKVFlags() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(kvBits: 0))
        XCTAssertFalse(args.contains("--kv-bits"))
        XCTAssertFalse(args.contains("--kv-group-size"))
        XCTAssertFalse(args.contains("--quantized-kv-start"))
    }

    func test_vlm_kvBitsNonZero_emitsKVFlags() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(kvBits: 4, kvGroupSize: 32, quantizedKvStart: 10))
        XCTAssertTrue(args.contains("--kv-bits"))
        let bitsIdx = args.firstIndex(of: "--kv-bits")!
        XCTAssertEqual(args[bitsIdx + 1], "4")
        XCTAssertTrue(args.contains("--kv-group-size"))
        let groupIdx = args.firstIndex(of: "--kv-group-size")!
        XCTAssertEqual(args[groupIdx + 1], "32")
        XCTAssertTrue(args.contains("--quantized-kv-start"))
        let startIdx = args.firstIndex(of: "--quantized-kv-start")!
        XCTAssertEqual(args[startIdx + 1], "10")
    }

    func test_vlm_maxKvSizeZero_omitFlag() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(maxKvSize: 0))
        XCTAssertFalse(args.contains("--max-kv-size"))
    }

    func test_vlm_maxKvSizeNonZero_emitFlag() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(maxKvSize: 2048))
        XCTAssertTrue(args.contains("--max-kv-size"))
        let idx = args.firstIndex(of: "--max-kv-size")!
        XCTAssertEqual(args[idx + 1], "2048")
    }

    func test_vlm_trustRemoteCode_omittedWhenFalse() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(trustRemoteCode: false))
        XCTAssertFalse(args.contains("--trust-remote-code"))
    }

    func test_vlm_trustRemoteCode_includedWhenTrue() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(trustRemoteCode: true))
        XCTAssertTrue(args.contains("--trust-remote-code"))
    }

    func test_vlm_extraArgs() {
        let args = MLXVlmArgBuilder().arguments(for: makeConfig(extraArgs: ["--foo", "bar"]))
        XCTAssertEqual(Array(args.suffix(2)), ["--foo", "bar"])
    }

    func test_vlm_fullArgListDefaults() {
        let config = ServerConfig(
            name: "v", model: "mlx-community/Qwen2.5-VL-7B-4bit", maxTokens: 0,
            port: 8082, prefillStepSize: 512,
            serverType: .mlxVLM, pythonPath: "/p"
        )
        let args = MLXVlmArgBuilder().arguments(for: config)
        XCTAssertEqual(args, [
            "-m", "mlx_vlm.server",
            "--model", "mlx-community/Qwen2.5-VL-7B-4bit",
            "--port", "8082",
            "--prefill-step-size", "512"
        ])
    }
}
