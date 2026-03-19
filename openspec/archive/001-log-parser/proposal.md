# Proposal: LogParser

## Motivation

Every other component (status bar, server manager) depends on interpreting the MLX
server log stream. Before any UI or process management exists, we need a pure,
well-tested function that turns raw log lines into typed events.

This is the foundational unit — zero external dependencies, fully testable in isolation.

## Scope

Implement `LogParser.swift`: a pure function `parse(line:) -> LogEvent?` that classifies
a single log line into one of:

- `.progress(current: Int, total: Int, percentage: Double)`
- `.kvCaches(gpuGB: Double, tokens: Int)` — also implies completion
- `.httpCompletion` — `POST /v1/chat/completions ... 200`
- `nil` — ignored/unrecognised line

No file I/O, no timers, no state. Pure input → output.

## Approach

1. Swift Package Manager project scaffold (no Xcode .xcodeproj needed for logic layer)
2. `LogEvent` enum as the output type
3. `LogParser.parse(line:)` static function with regex matching
4. XCTest suite driven entirely from the Gherkin scenarios in `openspec/specs/core/spec.md`
5. Red-Green TDD: one scenario → one failing test → minimal implementation → green
