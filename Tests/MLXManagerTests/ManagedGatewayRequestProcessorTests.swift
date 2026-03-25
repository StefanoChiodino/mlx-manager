import Foundation
import Testing
@testable import MLXManager

private final class MockGatewayUpstreamClient: GatewayUpstreamClient {
    var lastRequest: GatewayHTTPRequest?
    var response = GatewayHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: Data(#"{"id":"chatcmpl-test"}"#.utf8)
    )

    func send(_ request: GatewayHTTPRequest, routing: ManagedGatewayRouting) async throws -> GatewayHTTPResponse {
        lastRequest = request
        return response
    }
}

@Suite("ManagedGatewayRequestProcessor")
struct ManagedGatewayRequestProcessorTests {

    @Test("forwards rewritten requests to the upstream backend")
    func forwardsRewrittenRequests() async throws {
        let routing = ManagedGatewayRouting(config: ServerConfig.fixture(name: "27B Opus"))
        let upstream = MockGatewayUpstreamClient()
        let processor = ManagedGatewayRequestProcessor(
            routing: routing,
            upstreamClient: upstream
        )
        let body = #"{"model":"default","messages":[{"role":"user","content":"hi"}]}"#
        let rawRequest = """
        POST /v1/chat/completions HTTP/1.1\r
        Host: 127.0.0.1:8080\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        let responseData = await processor.process(rawRequest: Data(rawRequest.utf8))
        let forwarded = try #require(upstream.lastRequest)
        let json = try #require(JSONSerialization.jsonObject(with: forwarded.body) as? [String: Any])
        let responseText = try #require(String(data: responseData, encoding: .utf8))

        #expect(json["model"] as? String == routing.activeModel)
        #expect(responseText.contains("HTTP/1.1 200 OK"))
        #expect(responseText.contains(#"{"id":"chatcmpl-test"}"#))
    }

    @Test("answers synthetic model list requests without hitting the upstream backend")
    func answersSyntheticModelsList() async throws {
        let routing = ManagedGatewayRouting(config: ServerConfig.fixture(name: "4-bit 40k"))
        let upstream = MockGatewayUpstreamClient()
        let processor = ManagedGatewayRequestProcessor(
            routing: routing,
            upstreamClient: upstream
        )
        let rawRequest = """
        GET /v1/models HTTP/1.1\r
        Host: 127.0.0.1:8080\r
        \r
        
        """

        let responseData = await processor.process(rawRequest: Data(rawRequest.utf8))
        let responseText = try #require(String(data: responseData, encoding: .utf8))

        #expect(upstream.lastRequest == nil)
        #expect(responseText.contains("HTTP/1.1 200 OK"))
        #expect(responseText.contains(#""id":"default""#))
    }

    @Test("returns a 400 response for invalid HTTP requests")
    func returns400ForInvalidRequests() async throws {
        let routing = ManagedGatewayRouting(config: ServerConfig.fixture())
        let upstream = MockGatewayUpstreamClient()
        let processor = ManagedGatewayRequestProcessor(
            routing: routing,
            upstreamClient: upstream
        )

        let responseData = await processor.process(rawRequest: Data("not-http".utf8))
        let responseText = try #require(String(data: responseData, encoding: .utf8))

        #expect(responseText.contains("HTTP/1.1 400 Bad Request"))
        #expect(upstream.lastRequest == nil)
    }
}
