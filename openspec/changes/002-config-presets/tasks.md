# Tasks: Config Presets

Each task = one RED test written and confirmed failing, then GREEN implementation.

## Setup

- [x] Add Yams dependency to `Package.swift`
- [x] Create stub `Sources/MLXManager/ServerConfig.swift` (model type)
- [x] Create stub `Sources/MLXManager/ConfigLoader.swift` (returns empty array)
- [x] Create `Tests/MLXManagerTests/ConfigLoaderTests.swift` with all RED tests
- [x] Create `Resources/presets.yaml` with the 4 presets
- [x] Confirm `swift test` compiles — 9 new tests fail as expected (RED)

## Red-Green Cycles

- [x] **RED** `test_load_validYAML_returnsFourPresets` — returned 0, expected 4
- [x] **GREEN** implement YAML parsing with Yams + Codable DTOs
- [x] **RED→GREEN** `test_load_firstPreset_hasCorrectName` — name mapped correctly
- [x] **RED→GREEN** `test_load_4bit40k_hasThinkingDisabledArg` — extraArgs parsed
- [x] **RED→GREEN** `test_load_8bit80k_hasTrustRemoteCodeOnly` — correct
- [x] **RED→GREEN** `test_load_allPresets_haveTrustRemoteCode` — all 4 pass
- [x] **RED→GREEN** `test_load_allPresets_haveCorrectModels` — model names correct
- [x] **RED→GREEN** `test_load_allPresets_haveCorrectMaxTokens` — context sizes correct
- [x] **RED** `test_load_invalidYAML_throwsInvalidYAML` — no throw → fixed
- [x] **GREEN** error handling via YAMLDecoder catch
- [x] **RED** `test_load_missingModelField_throwsMissingField` — no throw → fixed
- [x] **GREEN** validate required fields with guard let

## Done

- [x] All tests green — 22/22 (9 new + 13 existing)
- [x] `swift test` output shows 0 failures
- [x] Commit: `feat(002-config-presets): implement ConfigLoader`
