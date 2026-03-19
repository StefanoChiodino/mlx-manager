# MLX Manager

A macOS menu bar application for managing MLX LLM server instances.

## Status: Spec Only

This repository contains the OpenSpec specification. Implementation is pending.

See [OpenSpec.md](OpenSpec.md) for complete requirements and design.

## Quick Reference

### Problem
- MLX server lacks "100%" completion signal in logs
- Manual start/stop commands are tedious
- No simple progress monitoring

### Solution
- Menu bar app with one-click controls
- Parse `Prompt processing progress: X/Y` for live progress
- Display GPU memory and completion status

### Config Presets
- 4-bit 40k (memory efficient)
- 4-bit 80k (balanced)
- 8-bit 40k (max quality)
- 8-bit 80k (large context)

## Next Steps

1. Choose tech stack: Swift or Python
2. Implement MVP (Phase 1)
3. Add settings panel (Phase 2)
