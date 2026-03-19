import XCTest
@testable import MLXManager

final class ServerConfigCodableTests: XCTestCase {

    func test_serverConfig_encodeDecode() throws {
        let config = ServerConfig(
            name: "Test",
            model: "some/model",
            maxTokens: 4096,
            extraArgs: ["--trust-remote-code"],
            pythonPath: "/usr/bin/python3"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }
}
