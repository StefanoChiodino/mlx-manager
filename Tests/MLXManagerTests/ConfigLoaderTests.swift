import XCTest
@testable import MLXManager

final class ConfigLoaderTests: XCTestCase {

    // MARK: - Test YAML fixture

    private let validYAML = """
    presets:
      - name: "4-bit 40k"
        model: "mlx-community/Qwen3.5-35B-A3B-4bit"
        maxTokens: 40960
        port: 8081
        prefillStepSize: 4096
        promptCacheSize: 4
        promptCacheBytes: 10737418240
        trustRemoteCode: true
        enableThinking: false
        pythonPath: "/custom/venv/bin/python3"
      - name: "4-bit 80k"
        model: "mlx-community/Qwen3.5-35B-A3B-4bit"
        maxTokens: 81920
        port: 8081
        prefillStepSize: 4096
        promptCacheSize: 4
        promptCacheBytes: 10737418240
        trustRemoteCode: true
        enableThinking: false
        pythonPath: "/custom/venv/bin/python3"
      - name: "8-bit 40k"
        model: "mlx-community/Qwen3.5-35B-A3B-8bit"
        maxTokens: 40960
        port: 8081
        prefillStepSize: 4096
        promptCacheSize: 4
        promptCacheBytes: 10737418240
        trustRemoteCode: true
        enableThinking: false
        pythonPath: "/custom/venv/bin/python3"
      - name: "8-bit 80k"
        model: "mlx-community/Qwen3.5-35B-A3B-8bit"
        maxTokens: 81920
        port: 8081
        prefillStepSize: 4096
        promptCacheSize: 4
        promptCacheBytes: 10737418240
        trustRemoteCode: true
        enableThinking: false
        pythonPath: "/custom/venv/bin/python3"
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

    /// Spec: 4-bit 40k preset has enableThinking = false
    func test_load_4bit40k_hasThinkingDisabledArg() throws {
        let presets = try loadValid()
        guard presets.count >= 1 else { return }
        let preset = presets[0]
        XCTAssertFalse(preset.enableThinking, "Expected enableThinking == false")
    }

    /// Spec: 8-bit 80k preset has no extra args (trustRemoteCode is a field, not extraArgs)
    func test_load_8bit80k_hasTrustRemoteCodeOnly() throws {
        let presets = try loadValid()
        guard presets.count >= 4 else { return }
        let preset = presets[3]
        XCTAssertTrue(preset.trustRemoteCode, "Expected trustRemoteCode == true")
        XCTAssertEqual(preset.extraArgs, [])
    }

    /// Spec: All presets have trustRemoteCode = true
    func test_load_allPresets_haveTrustRemoteCode() throws {
        let presets = try loadValid()
        for preset in presets {
            XCTAssertTrue(
                preset.trustRemoteCode,
                "\(preset.name) missing trustRemoteCode"
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

    /// pythonPath is loaded from YAML
    func test_load_allPresets_havePythonPath() throws {
        let presets = try loadValid()
        for preset in presets {
            XCTAssertEqual(preset.pythonPath, "/custom/venv/bin/python3",
                           "\(preset.name) has wrong pythonPath")
        }
    }

    /// pythonPath defaults to the backend-managed environment when omitted
    func test_load_missingPythonPathField_usesBackendDefault() throws {
        let yaml = """
        presets:
          - name: "broken"
            model: "some-model"
            maxTokens: 40960
            serverType: "mlxVLM"
        """
        let presets = try ConfigLoader.load(yaml: yaml)
        XCTAssertEqual(presets[0].pythonPath, EnvironmentBootstrapper.pythonPath(for: .mlxVLM))
    }

    /// port defaults to 8080 when not specified
    func test_load_missingPortField_usesDefault() throws {
        let yaml = """
        presets:
          - name: "test"
            model: "some-model"
            maxTokens: 40960
            pythonPath: "/usr/bin/python3"
        """
        let presets = try ConfigLoader.load(yaml: yaml)
        XCTAssertEqual(presets[0].port, 8080)
    }

    /// trustRemoteCode defaults to false when not specified
    func test_load_missingTrustRemoteCodeField_usesDefault() throws {
        let yaml = """
        presets:
          - name: "test"
            model: "some-model"
            maxTokens: 40960
            pythonPath: "/usr/bin/python3"
        """
        let presets = try ConfigLoader.load(yaml: yaml)
        XCTAssertEqual(presets[0].trustRemoteCode, false)
    }

    /// enableThinking defaults to false when not specified
    func test_load_missingEnableThinkingField_usesDefault() throws {
        let yaml = """
        presets:
          - name: "test"
            model: "some-model"
            maxTokens: 40960
            pythonPath: "/usr/bin/python3"
        """
        let presets = try ConfigLoader.load(yaml: yaml)
        XCTAssertEqual(presets[0].enableThinking, false)
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
