import Foundation

/// Abstraction over the outbound HTTP hop from the gateway to the hidden backend server.
public protocol GatewayUpstreamClient {
    func send(_ request: GatewayHTTPRequest, routing: ManagedGatewayRouting) async throws -> GatewayHTTPResponse
}

/// URLSession-backed upstream client used by the real managed gateway.
public final class URLSessionGatewayUpstreamClient: GatewayUpstreamClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: GatewayHTTPRequest, routing: ManagedGatewayRouting) async throws -> GatewayHTTPResponse {
        guard let url = URL(string: "http://127.0.0.1:\(routing.backendPort)\(request.path)") else {
            throw URLError(.badURL)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        if !request.body.isEmpty {
            urlRequest.httpBody = request.body
        }

        for (name, value) in request.headers {
            switch name.lowercased() {
            case "host", "content-length", "connection":
                continue
            default:
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        var headers: [String: String] = [:]
        for (name, value) in httpResponse.allHeaderFields {
            guard let key = name as? String, let stringValue = value as? String else { continue }
            switch key.lowercased() {
            case "content-length", "connection":
                continue
            default:
                headers[key] = stringValue
            }
        }

        return GatewayHTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data
        )
    }
}

/// Converts raw socket bytes into a serialized HTTP response for the managed gateway.
public struct ManagedGatewayRequestProcessor {
    private let routing: ManagedGatewayRouting
    private let handler: ManagedGatewayRequestHandler
    private let upstreamClient: GatewayUpstreamClient

    public init(routing: ManagedGatewayRouting, upstreamClient: GatewayUpstreamClient) {
        self.routing = routing
        self.handler = ManagedGatewayRequestHandler(routing: routing)
        self.upstreamClient = upstreamClient
    }

    public func process(rawRequest: Data) async -> Data {
        guard let request = GatewayHTTPCodec.parseRequest(from: rawRequest) else {
            return GatewayHTTPCodec.serialize(response: errorResponse(statusCode: 400, message: "invalid gateway request"))
        }

        do {
            let decision = try handler.handle(request: request)
            switch decision {
            case let .respond(response):
                return GatewayHTTPCodec.serialize(response: response)
            case let .forward(forwardedRequest):
                let upstreamResponse = try await upstreamClient.send(forwardedRequest, routing: routing)
                return GatewayHTTPCodec.serialize(response: upstreamResponse)
            }
        } catch {
            return GatewayHTTPCodec.serialize(response: errorResponse(statusCode: 502, message: "backend request failed"))
        }
    }

    private func errorResponse(statusCode: Int, message: String) -> GatewayHTTPResponse {
        let payload: [String: Any] = ["error": ["message": message]]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return GatewayHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }
}
