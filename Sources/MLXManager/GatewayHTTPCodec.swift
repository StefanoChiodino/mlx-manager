import Foundation

/// Small HTTP/1.1 codec for the gateway's one-request-per-connection server model.
public enum GatewayHTTPCodec {
    public static func parseRequest(from data: Data) -> GatewayHTTPRequest? {
        let headerSeparator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: headerSeparator) else { return nil }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else { return nil }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = headerRange.upperBound
        let contentLength = Int(headers["Content-Length"] ?? "") ?? 0
        let availableBytes = data.count - bodyStart
        guard availableBytes >= contentLength else { return nil }
        let bodyEnd = bodyStart + contentLength
        let body = data[bodyStart..<bodyEnd]

        return GatewayHTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: Data(body)
        )
    }

    public static func serialize(response: GatewayHTTPResponse) -> Data {
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"

        var lines = ["HTTP/1.1 \(response.statusCode) \(reasonPhrase(for: response.statusCode))"]
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): \(value)")
        }
        lines.append("")
        lines.append("")

        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(response.body)
        return data
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 411: return "Length Required"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "HTTP Response"
        }
    }
}
