import XCTest
@testable import MLXManager

final class ConfigLoaderTests: XCTestCase {

    // MARK: - Test YAML fixture

    private let validYAML = """
    presets:
      - name: "4-bit 40k"
        model: "mlx-community/Qwen3.5-35B-A3B-4bit"
        maxTokens: 40960
        extraArgs:
          - "--trust-remote-code"
          - "--chat-template-args"
          - '{"enable_thinking":false}'
      - name: "4-bit 80k"
        model: "mlx-community/Qwen3.5-35B-A3B-4bit"
        maxTokens: 81920
        extraArgs:
          - "--trust-remote-code"
      - name: "8-bit 40k"
        model: "mlx-community/Qwen3.5-35B-A3B-8bit"
        maxTokens: 40960
        extraArgs:
          - "--trust-remote-code"
      - name: "8-bit 80k"
        model: "mlx-community/Qwen3.5-35B-A3B-8bit"
        maxTokens: 81920
        extraArgs:
          - "--trust-remote-code"
    """

    // MARK: - Helpers

    private func loadValid() throws -> [ServerConfig] {
        let presets = try ConfigLoader.load(yaml: validYAML)
        guard presets.count == 4 else {
            XCTFail("Expected 4 presets, got \(presets.count)")
            return presets
        }
        return presets
    }

    // MARK: - Happy path

    /// Spec: Preset loading — returns exactly 4 presets
    func test_load_validYAML_returnsFourPresets() throws {
        let presets = try ConfigLoader.load(yaml: validYAML)
        XCTAssertEqual(presets.count, 4)
    }

    /// Spec: First preset has correct name
    func test_load_firstPreset_hasCorrectName() throws {
        let presets = try loadValid()
        guard presets.count >= 1 else { return }
        XCTAssertEqual(presets[0].name, "4-bit 40k")
    }

    /// Spec: 4-bit 40k preset includes --chat-template-args with thinking disabled
    func test_load_4bit40k_hasThinkingDisabledArg() throws {
        let presets = try loadValid()
        guard presets.count >= 1 else { return }
        let preset = presets[0]
        XCTAssertTrue(preset.extraArgs.contains("--chat-template-args"),
                      "Missing --chat-template-args")
        XCTAssertTrue(preset.extraArgs.contains(#"{"enable_thinking":false}"#),
                      "Missing thinking disabled JSON")
    }

    /// Spec: 8-bit 80k preset has only --trust-remote-code
    func test_load_8bit80k_hasTrustRemoteCodeOnly() throws {
        let presets = try loadValid()
        guard presets.count >= 4 else { return }
        let preset = presets[3]
        XCTAssertEqual(preset.extraArgs, ["--trust-remote-code"])
    }

    /// Spec: All presets include --trust-remote-code
    func test_load_allPresets_haveTrustRemoteCode() throws {
        let presets = try loadValid()
        for preset in presets {
            XCTAssertTrue(
                preset.extraArgs.contains("--trust-remote-code"),
                "\(preset.name) missing --trust-remote-code"
            )
        }
    }

    /// Verify model names are correct across all presets
    func test_load_allPresets_haveCorrectModels() throws {
        let presets = try loadValid()
        guard presets.count >= 4 else { return }
        XCTAssertEqual(presets[0].model, "mlx-community/Qwen3.5-35B-A3B-4bit")
        XCTAssertEqual(presets[1].model, "mlx-community/Qwen3.5-35B-A3B-4bit")
        XCTAssertEqual(presets[2].model, "mlx-community/Qwen3.5-35B-A3B-8bit")
        XCTAssertEqual(presets[3].model, "mlx-community/Qwen3.5-35B-A3B-8bit")
    }

    /// Verify context sizes are correct across all presets
    func test_load_allPresets_haveCorrectMaxTokens() throws {
        let presets = try loadValid()
        guard presets.count >= 4 else { return }
        XCTAssertEqual(presets[0].maxTokens, 40960)
        XCTAssertEqual(presets[1].maxTokens, 81920)
        XCTAssertEqual(presets[2].maxTokens, 40960)
        XCTAssertEqual(presets[3].maxTokens, 81920)
    }

    // MARK: - Error cases

    /// Invalid YAML throws .invalidYAML
    func test_load_invalidYAML_throwsInvalidYAML() {
        let badYAML = "{{not valid yaml: [}"
        XCTAssertThrowsError(try ConfigLoader.load(yaml: badYAML)) { error in
            XCTAssertEqual(error as? ConfigError, .invalidYAML)
        }
    }

    /// Missing required 'model' field throws .missingField
    func test_load_missingModelField_throwsMissingField() {
        let yaml = """
        presets:
          - name: "broken"
            maxTokens: 40960
            extraArgs:
              - "--trust-remote-code"
        """
        XCTAssertThrowsError(try ConfigLoader.load(yaml: yaml)) { error in
            XCTAssertEqual(error as? ConfigError, .missingField("model"))
        }
    }
}
