import Foundation
import Testing
@testable import MLXManager

@Suite("GatewayHTTPCodec")
struct GatewayHTTPCodecTests {

    @Test("parses a complete HTTP request with headers and body")
    func parsesCompleteRequest() throws {
        let body = #"{"model":"default","messages":[]}"#
        let raw = """
        POST /v1/chat/completions HTTP/1.1\r
        Host: 127.0.0.1:8080\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        let request = try #require(GatewayHTTPCodec.parseRequest(from: Data(raw.utf8)))

        #expect(request.method == "POST")
        #expect(request.path == "/v1/chat/completions")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(String(data: request.body, encoding: .utf8) == body)
    }

    @Test("returns nil while the body is incomplete")
    func returnsNilForIncompleteBody() {
        let raw = """
        POST /v1/chat/completions HTTP/1.1\r
        Content-Type: application/json\r
        Content-Length: 20\r
        \r
        {"model":"default"
        """

        #expect(GatewayHTTPCodec.parseRequest(from: Data(raw.utf8)) == nil)
    }

    @Test("serializes a response with status line content length and connection close")
    func serializesResponse() throws {
        let response = GatewayHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"ok":true}"#.utf8)
        )

        let data = GatewayHTTPCodec.serialize(response: response)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.contains("Content-Length: 11\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{\"ok\":true}"))
    }
}
