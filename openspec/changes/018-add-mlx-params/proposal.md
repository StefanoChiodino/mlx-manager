# Proposal: Add MLX Server Parameters

## Problem

The current `ServerConfig` struct only supports `name`, `model`, `maxTokens`, `extraArgs`, and `pythonPath`. The original `serve.sh` script includes critical performance parameters that are missing:

```bash
--port "$PORT" \
--prefill-step-size 4096 \
--max-tokens 32768 \
--prompt-cache-size 4 \
--prompt-cache-bytes $((10 * 1024 * 1024 * 1024))
```

Without these parameters, the server runs with suboptimal defaults, leading to:
- Performance degradation from missing prefill step size
- Limited concurrent cached requests (default cache size is 10, but we use 4)
- No control over prompt cache memory budget

Additionally, `trust-remote-code` and `enable_thinking` flags should be explicit boolean parameters, not arbitrary strings in `extraArgs`.

## Solution

Add the following fields to `ServerConfig`:
- `port: Int` (default: 8080) - Server listening port
- `prefillStepSize: Int` (default: 4096) - Memory optimization for prefill
- `promptCacheSize: Int` (default: 4) - LRU cache slots
- `promptCacheBytes: Int` (default: 10GB) - Memory budget for cache
- `trustRemoteCode: Bool` (default: false) - Code execution flag
- `enableThinking: Bool` (default: false) - Thinking mode toggle

## Impact

- Presets will now match the optimized `serve.sh` configuration
- Users can customize all server parameters through the UI
- Backward compatible with existing presets via defaults
