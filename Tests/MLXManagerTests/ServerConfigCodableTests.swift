import XCTest
@testable import MLXManager

final class ServerConfigCodableTests: XCTestCase {

    func test_serverConfig_encodeDecode() throws {
        let config = ServerConfig(
            name: "Test",
            model: "some/model",
            maxTokens: 4096,
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
            extraArgs: ["--trust-remote-code"],
            pythonPath: "/usr/bin/python3"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func test_serverConfig_defaultValues() throws {
        let config = ServerConfig(
            name: "Test",
            model: "some/model",
            maxTokens: 4096,
            pythonPath: "/usr/bin/python3"
        )
        XCTAssertEqual(config.port, 8080)
        XCTAssertEqual(config.prefillStepSize, 4096)
        XCTAssertEqual(config.promptCacheSize, 4)
        XCTAssertEqual(config.promptCacheBytes, 10 * 1024 * 1024 * 1024)
        XCTAssertEqual(config.trustRemoteCode, false)
        XCTAssertEqual(config.enableThinking, false)
    }

    func test_serverConfig_allValues() throws {
        let config = ServerConfig(
            name: "Test",
            model: "some/model",
            maxTokens: 8192,
            port: 9000,
            prefillStepSize: 2048,
            promptCacheSize: 8,
            promptCacheBytes: 5 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: true,
            extraArgs: ["--trust-remote-code"],
            pythonPath: "/usr/bin/python3"
        )
        XCTAssertEqual(config.port, 9000)
        XCTAssertEqual(config.prefillStepSize, 2048)
        XCTAssertEqual(config.promptCacheSize, 8)
        XCTAssertEqual(config.promptCacheBytes, 5 * 1024 * 1024 * 1024)
        XCTAssertEqual(config.trustRemoteCode, true)
        XCTAssertEqual(config.enableThinking, true)
    }

    func test_serverConfig_encodeDecode_allValues() throws {
        let config = ServerConfig(
            name: "Test",
            model: "some/model",
            maxTokens: 8192,
            port: 9000,
            prefillStepSize: 2048,
            promptCacheSize: 8,
            promptCacheBytes: 5 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: true,
            extraArgs: ["--trust-remote-code"],
            pythonPath: "/usr/bin/python3"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }
}

final class ServerConfigVLMFieldTests: XCTestCase {

    func test_vlmFieldDefaults() {
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024, pythonPath: "/usr/bin/python3"
        )
        XCTAssertEqual(config.kvBits, 0)
        XCTAssertEqual(config.kvGroupSize, 64)
        XCTAssertEqual(config.maxKvSize, 0)
        XCTAssertEqual(config.quantizedKvStart, 0)
    }

    func test_vlmFieldsRoundTrip() throws {
        let original = ServerConfig(
            name: "vlm", model: "m", maxTokens: 0,
            kvBits: 4, kvGroupSize: 32, maxKvSize: 2048, quantizedKvStart: 100,
            pythonPath: "/p"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_withResolvedPythonPath_expandsTilde() {
        let config = ServerConfig(
            name: "t", model: "m", maxTokens: 1, pythonPath: "~/.mlx-manager/venv/bin/python"
        )
        let resolved = config.withResolvedPythonPath()
        XCTAssertFalse(resolved.pythonPath.hasPrefix("~"))
        XCTAssertTrue(resolved.pythonPath.contains(".mlx-manager/venv/bin/python"))
    }

    func test_withResolvedPythonPath_absolutePath_unchanged() {
        let config = ServerConfig(
            name: "t", model: "m", maxTokens: 1, pythonPath: "/usr/bin/python3"
        )
        let resolved = config.withResolvedPythonPath()
        XCTAssertEqual(resolved.pythonPath, "/usr/bin/python3")
    }

    func test_withResolvedPythonPath_preservesAllFields() {
        let config = ServerConfig(
            name: "n", model: "mod", maxTokens: 99, port: 9999,
            prefillStepSize: 512, promptCacheSize: 3, promptCacheBytes: 5000,
            trustRemoteCode: true, enableThinking: true,
            extraArgs: ["--foo"], serverType: .mlxVLM,
            kvBits: 8, kvGroupSize: 16, maxKvSize: 1024, quantizedKvStart: 50,
            pythonPath: "~/.mlx-manager/venv-vlm/bin/python"
        )
        let resolved = config.withResolvedPythonPath()
        XCTAssertEqual(resolved.name, "n")
        XCTAssertEqual(resolved.model, "mod")
        XCTAssertEqual(resolved.maxTokens, 99)
        XCTAssertEqual(resolved.port, 9999)
        XCTAssertEqual(resolved.prefillStepSize, 512)
        XCTAssertEqual(resolved.promptCacheSize, 3)
        XCTAssertEqual(resolved.promptCacheBytes, 5000)
        XCTAssertEqual(resolved.trustRemoteCode, true)
        XCTAssertEqual(resolved.enableThinking, true)
        XCTAssertEqual(resolved.extraArgs, ["--foo"])
        XCTAssertEqual(resolved.serverType, .mlxVLM)
        XCTAssertEqual(resolved.kvBits, 8)
        XCTAssertEqual(resolved.kvGroupSize, 16)
        XCTAssertEqual(resolved.maxKvSize, 1024)
        XCTAssertEqual(resolved.quantizedKvStart, 50)
        // The tilde should be expanded
        XCTAssertFalse(resolved.pythonPath.hasPrefix("~"))
        XCTAssertTrue(resolved.pythonPath.contains(".mlx-manager/venv-vlm/bin/python"))
    }

    func test_decode_withoutServerTypeKey_defaultsToMLXLM() throws {
        // Minimal old preset JSON — no serverType, no VLM fields
        let json = """
        {
            "name": "old",
            "model": "m",
            "maxTokens": 1024,
            "port": 8080,
            "prefillStepSize": 4096,
            "promptCacheSize": 4,
            "promptCacheBytes": 10737418240,
            "trustRemoteCode": false,
            "enableThinking": false,
            "extraArgs": [],
            "pythonPath": "/usr/bin/python3"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: json)
        XCTAssertEqual(decoded.serverType, .mlxLM)
        XCTAssertEqual(decoded.kvBits, 0)
        XCTAssertEqual(decoded.kvGroupSize, 64)
        XCTAssertEqual(decoded.maxKvSize, 0)
        XCTAssertEqual(decoded.quantizedKvStart, 0)
    }
}
