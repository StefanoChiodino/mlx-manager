# Proposal: Config Presets

## Problem

The app needs to load server configuration presets so the user can select which model/context combination to launch. Currently there is no config loading mechanism.

## Solution

Implement `ConfigLoader` — a pure function that parses a YAML string into an array of `ServerConfig` value types. Ship a bundled `presets.yaml` with the four required presets.

## Scope

- `ServerConfig` model type
- `ConfigLoader.load(yaml:)` parser
- Bundled `presets.yaml` resource file
- Full XCTest coverage

## Out of Scope

- UI for selecting presets (future change)
- Runtime config editing
- Server launch integration (depends on ServerManager)
