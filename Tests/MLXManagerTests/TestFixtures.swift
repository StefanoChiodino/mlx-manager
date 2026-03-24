import Foundation
@testable import MLXManager

// MARK: - Shared Test Fixtures

extension ServerConfig {
    static func fixture(
        name: String = "Test",
        pythonPath: String = "/usr/bin/python3"
    ) -> ServerConfig {
        ServerConfig(
            name: name,
            model: "mlx-community/test-model",
            maxTokens: 4096,
            pythonPath: pythonPath
        )
    }
}
