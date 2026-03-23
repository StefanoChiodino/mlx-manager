import XCTest
@testable import MLXManager

final class UserPresetStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".yaml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func test_userPresetStore_saveAndLoad() throws {
        let presets = [
            ServerConfig(name: "Test", model: "some/model", maxTokens: 4096,
                         extraArgs: ["--trust-remote-code"], pythonPath: "/usr/bin/python3")
        ]
        try UserPresetStore.save(presets, to: tempURL)
        let loaded = try UserPresetStore.load(from: tempURL)
        XCTAssertEqual(loaded, presets)
    }

    func test_userPresetStore_roundTrip_preservesAllFields() throws {
        let preset = ServerConfig(
            name: "Full",
            model: "mlx-community/full-model",
            maxTokens: 8192,
            port: 9090,
            prefillStepSize: 2048,
            promptCacheSize: 8,
            promptCacheBytes: 5 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: true,
            extraArgs: ["--verbose"],
            serverType: .mlxVLM,
            kvBits: 4,
            kvGroupSize: 32,
            maxKvSize: 512,
            quantizedKvStart: 100,
            pythonPath: "/usr/local/bin/python3"
        )
        try UserPresetStore.save([preset], to: tempURL)
        let loaded = try UserPresetStore.load(from: tempURL)
        XCTAssertEqual(loaded, [preset])
    }

    func test_userPresetStore_loadMissingFileThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).yaml")
        XCTAssertThrowsError(try UserPresetStore.load(from: missing))
    }
}
