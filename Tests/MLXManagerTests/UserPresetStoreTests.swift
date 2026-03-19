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

    func test_userPresetStore_loadMissingFileThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).yaml")
        XCTAssertThrowsError(try UserPresetStore.load(from: missing))
    }
}
