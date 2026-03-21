import Testing
import Foundation
@testable import MLXManager

// MARK: - Tests for ServerType enum and ServerConfig

@Suite("ServerType")
struct ServerTypeTests {

    @Test("has MLX_LM case")
    func test_hasMLXLMCase() async throws {
        #expect(ServerType.mlxLM == ServerType.mlxLM)
    }

    @Test("has MLX_VLM case")
    func test_hasMLXVLMCase() async throws {
        #expect(ServerType.mlxVLM == ServerType.mlxVLM)
    }

    @Test("has descriptiveName property")
    func test_descriptiveName() async throws {
        #expect(ServerType.mlxLM.descriptiveName == "MLX-LM (text)")
        #expect(ServerType.mlxVLM.descriptiveName == "MLX-VLM (vision)")
    }

    @Test("has serverModule property")
    func test_serverModule() async throws {
        #expect(ServerType.mlxLM.serverModule == "mlx_lm.server")
        #expect(ServerType.mlxVLM.serverModule == "mlx_vlm.server")
    }

    @Test("has serverEntryName property")
    func test_serverEntryName() async throws {
        #expect(ServerType.mlxLM.serverEntryName == "mlx_lm.server")
        #expect(ServerType.mlxVLM.serverEntryName == "mlx_vlm.server")
    }
}

@Suite("ServerConfig - ServerType")
struct ServerConfigServerTypeTests {

    @Test("has serverType property defaulting to MLX_LM")
    func test_defaultServerType() async throws {
        let config = ServerConfig(
            name: "test",
            model: "test-model",
            maxTokens: 4096,
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
            extraArgs: [],
            pythonPath: "/usr/bin/python"
        )
        #expect(config.serverType == ServerType.mlxLM)
    }

    @Test("can be initialized with MLX_VLM")
    func test_initWithMLXVLM() async throws {
        let config = ServerConfig(
            name: "vision-test",
            model: "mlx-community/llama4-1b-it-4bit",
            maxTokens: 4096,
            serverType: .mlxVLM,
            pythonPath: "/usr/bin/python"
        )
        #expect(config.serverType == ServerType.mlxVLM)
        #expect(config.name == "vision-test")
    }

    @Test("codable - serializes with MLX_VLM")
    func test_codableMLXVLM() async throws {
        let config = ServerConfig(
            name: "vision-test",
            model: "mlx-community/llama4-1b-it-4bit",
            maxTokens: 4096,
            serverType: .mlxVLM,
            pythonPath: "/usr/bin/python"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("serverType"), "Expected serverType field in JSON")
        #expect(json.contains("mlxVLM"), "Expected serverType value to be mlxVLM")
    }

    @Test("codable - deserializes with MLX_VLM")
    func test_codableDeserialization() async throws {
        let json = """
        {
            "name": "test",
            "model": "mlx-community/test",
            "maxTokens": 4096,
            "port": 8080,
            "prefillStepSize": 4096,
            "promptCacheSize": 4,
            "promptCacheBytes": 10737418240,
            "trustRemoteCode": false,
            "enableThinking": false,
            "extraArgs": [],
            "serverType": "mlxVLM",
            "pythonPath": "/usr/bin/python"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let config = try decoder.decode(ServerConfig.self, from: data)
        #expect(config.serverType == ServerType.mlxVLM)
    }

    @Test("codable - serializes with MLX_LM")
    func test_codableMLXLM() async throws {
        let config = ServerConfig(
            name: "text-test",
            model: "mlx-community/Qwen3.5-35B-A3B-4bit",
            maxTokens: 4096,
            serverType: .mlxLM,
            pythonPath: "/usr/bin/python"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"serverType\":\"mlxLM\""))
    }

    @Test("codable - deserializes with MLX_LM")
    func test_codableDeserializationMLXLM() async throws {
        let json = """
        {
            "name": "test",
            "model": "mlx-community/test",
            "maxTokens": 4096,
            "port": 8080,
            "prefillStepSize": 4096,
            "promptCacheSize": 4,
            "promptCacheBytes": 10737418240,
            "trustRemoteCode": false,
            "enableThinking": false,
            "extraArgs": [],
            "serverType": "mlxLM",
            "pythonPath": "/usr/bin/python"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let config = try decoder.decode(ServerConfig.self, from: data)
        #expect(config.serverType == ServerType.mlxLM)
    }
}
