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
