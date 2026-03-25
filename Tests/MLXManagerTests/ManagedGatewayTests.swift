import Foundation
import Testing
@testable import MLXManager

@Suite("ManagedGateway")
struct ManagedGatewayTests {

    @Test("routing moves the backend to a hidden offset port")
    func routingMovesBackendToHiddenOffsetPort() {
        let config = ServerConfig(
            name: "4-bit 40k",
            model: "mlx-community/Qwen3.5-35B-A3B-4bit",
            maxTokens: 40960,
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: false,
            extraArgs: [],
            pythonPath: "/Users/stefano/.mlx-manager/venv/bin/python"
        )

        let routing = ManagedGatewayRouting(config: config)

        #expect(routing.publicPort == 8080)
        #expect(routing.backendPort == 8180)
        #expect(routing.backendConfig.port == 8180)
        #expect(routing.backendConfig.model == config.model)
    }

    @Test("recovered routing matches a managed backend launched with global proxy and server ports")
    func recoveredRoutingMatchesManagedBackend() {
        let config = ServerConfig(
            name: "27B Opus",
            model: "mlx-community/Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-6bit",
            maxTokens: 40960,
            port: 9999,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: true,
            extraArgs: [],
            pythonPath: "/Users/stefano/.mlx-manager/venv/bin/python"
        )
        var settings = AppSettings()
        settings.serverPort = 8088
        settings.managedGatewayPort = 8080
        let discovered = DiscoveredServer(
            pid: 101,
            command: config.pythonPath,
            arguments: [
                "-m", "mlx_lm.server",
                "--model", config.model,
                "--port", "8088",
            ],
            serverType: .mlxLM,
            model: config.model,
            port: 8088
        )

        let recovered = ManagedGatewayRouting.recovered(server: discovered, presets: [config], settings: settings)

        #expect(recovered?.publicPort == 8080)
        #expect(recovered?.backendPort == 8088)
        #expect(recovered?.activeModel == config.model)
    }

    @Test("request handler rewrites the default model alias to the active model")
    func requestHandlerRewritesDefaultAlias() throws {
        let routing = ManagedGatewayRouting(config: ServerConfig.fixture(name: "4-bit 40k"))
        let request = GatewayHTTPRequest(
            method: "POST",
            path: "/v1/chat/completions",
            headers: ["Content-Type": "application/json"],
            body: try #require("""
            {"model":"default","messages":[{"role":"user","content":"hi"}]}
            """.data(using: .utf8))
        )

        let decision = try ManagedGatewayRequestHandler(routing: routing).handle(request: request)
        guard case let .forward(forwarded) = decision else {
            Issue.record("Expected request to be forwarded")
            return
        }

        let json = try #require(JSONSerialization.jsonObject(with: forwarded.body) as? [String: Any])
        #expect(json["model"] as? String == routing.activeModel)
    }

    @Test("request handler rewrites the preset name alias to the active model")
    func requestHandlerRewritesPresetNameAlias() throws {
        let config = ServerConfig.fixture(name: "27B Opus")
        let routing = ManagedGatewayRouting(config: config)
        let request = GatewayHTTPRequest(
            method: "POST",
            path: "/v1/responses",
            headers: ["Content-Type": "application/json"],
            body: try #require("""
            {"model":"27B Opus","input":"hello"}
            """.data(using: .utf8))
        )

        let decision = try ManagedGatewayRequestHandler(routing: routing).handle(request: request)
        guard case let .forward(forwarded) = decision else {
            Issue.record("Expected request to be forwarded")
            return
        }

        let json = try #require(JSONSerialization.jsonObject(with: forwarded.body) as? [String: Any])
        #expect(json["model"] as? String == routing.activeModel)
    }

    @Test("request handler synthesizes a models list with only the default alias")
    func requestHandlerSynthesizesModelsList() throws {
        let config = ServerConfig.fixture(name: "27B Opus")
        let routing = ManagedGatewayRouting(config: config)
        let request = GatewayHTTPRequest(
            method: "GET",
            path: "/v1/models",
            headers: [:],
            body: Data()
        )

        let decision = try ManagedGatewayRequestHandler(routing: routing).handle(request: request)
        guard case let .respond(response) = decision else {
            Issue.record("Expected synthetic models response")
            return
        }

        #expect(response.statusCode == 200)
        let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let data = try #require(json["data"] as? [[String: Any]])
        let ids = data.compactMap { $0["id"] as? String }
        #expect(ids == ["default"])
    }
}
