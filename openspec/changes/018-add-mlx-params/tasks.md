# Tasks: Add MLX Server Parameters

## Implementation Tasks

- [x] Add new fields to `ServerConfig` struct with defaults
- [x] Update `ServerManager.start()` to use new fields
- [x] Update `SettingsWindowController` table columns
- [x] Update `ConfigLoader.PresetDTO` with new fields
- [x] Update `presets.yaml` with serve.sh parameters
- [x] Update tests to use new fields
- [x] Rebuild and install app

## Test Cases

### ServerConfig Tests

1. **Default values**
   - Given new ServerConfig with minimal params
   - When created
   - Then port=8080, prefillStepSize=4096, promptCacheSize=4, promptCacheBytes=10GB, trustRemoteCode=false, enableThinking=false

2. **Explicit values**
   - Given ServerConfig with all params specified
   - When created
   - Then all values match input

3. **Codable encoding/decoding**
   - Given ServerConfig instance
   - When encoded to JSON and decoded
   - Then round-trips correctly

### ServerManager Tests

4. **Argument construction**
   - Given ServerConfig with port=8081, prefillStepSize=4096, promptCacheSize=4, promptCacheBytes=10737418240
   - When start(config:) is called
   - Then arguments include --port 8081, --prefill-step-size 4096, --prompt-cache-size 4, --prompt-cache-bytes 10737418240

5. **trustRemoteCode flag**
   - Given ServerConfig(trustRemoteCode: true)
   - When start(config:) is called
   - Then --trust-remote-code is in arguments

6. **enableThinking flag**
   - Given ServerConfig(enableThinking: true)
   - When start(config:) is called
   - Then --chat-template-args "{\"enable_thinking\":true}" is in arguments

7. **enableThinking=false**
   - Given ServerConfig(enableThinking: false)
   - When start(config:) is called
   - Then --chat-template-args "{\"enable_thinking\":false}" is in arguments

### ConfigLoader Tests

8. **Load preset with all fields**
   - Given YAML with port, prefillStepSize, promptCacheSize, promptCacheBytes, trustRemoteCode, enableThinking
   - When load(yaml:) is called
   - Then ServerConfig has all values

9. **Load preset without new fields**
   - Given YAML without port, prefillStepSize, etc.
   - When load(yaml:) is called
   - Then defaults are used

10. **Load trustRemoteCode: true**
    - Given YAML with trustRemoteCode: true
    - When load(yaml:) is called
    - Then ServerConfig.trustRemoteCode == true

11. **Load enableThinking: true**
    - Given YAML with enableThinking: true
    - When load(yaml:) is called
    - Then ServerConfig.enableThinking == true

### UI Tests

12. **Render table columns**
    - Given SettingsWindowController with presets
    - When window appears
    - Then table shows port, prefillStepSize, promptCacheSize, promptCacheBytes, trustRemoteCode, enableThinking columns

13. **Edit port value**
    - Given row with port=8081
    - When user edits cell to "9000"
    - Then preset.port == 9000

14. **Edit trustRemoteCode checkbox**
    - Given row with trustRemoteCode=false
    - When user edits cell to "✓"
    - Then preset.trustRemoteCode == true

15. **Edit enableThinking checkbox**
    - Given row with enableThinking=false
    - When user edits cell to "✓"
    - Then preset.enableThinking == true

### Integration Tests

16. **Start server with preset**
    - Given preset with all new fields
    - When server starts
    - Then process receives correct arguments

17. **YAML round-trip**
    - Given presets.yaml file
    - When loaded and re-saved
    - Then content matches original

## Acceptance Criteria

- [x] Build succeeds
- [x] All tests pass (76 tests)
- [ ] UI shows new columns (manual test)
- [ ] Server starts with correct arguments from serve.sh (manual test)
- [ ] presets.yaml loads with all parameters (manual test)
