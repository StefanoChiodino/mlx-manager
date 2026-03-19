# Design: LogParser

## Output Type

```swift
enum LogEvent: Equatable {
    case progress(current: Int, total: Int, percentage: Double)
    case kvCaches(gpuGB: Double, tokens: Int)
    case httpCompletion
}
```

`kvCaches` and `httpCompletion` are both completion signals — the state machine
(future change) will treat them equivalently.

## API

```swift
enum LogParser {
    static func parse(line: String) -> LogEvent?
}
```

Pure function. No side effects. No state.

## Regex Patterns (from real log evidence)

```
Progress : "Prompt processing progress: (\d+)/(\d+)"
KV Caches: "KV Caches: \d+ seq, ([\d.]+) GB, latest user cache (\d+) tokens"
HTTP 200 : "POST /v1/chat/completions HTTP/1\.1\" 200"
```

## File Layout

```
Sources/MLXManager/LogParser.swift
Tests/MLXManagerTests/LogParserTests.swift
Package.swift
```

## Test Mapping (Gherkin → XCTest)

Each scenario in `openspec/specs/core/spec.md` maps to exactly one test method:

| Scenario | Test method |
|----------|-------------|
| Valid progress line — mid-request | `test_parse_progressLine_returnsMidRequestEvent` |
| Valid progress line — near end | `test_parse_progressNearEnd_returnsNotComplete` |
| Non-progress line | `test_parse_kvCachesLine_returnsNilForProgressParse` |
| Valid KV Caches line | `test_parse_kvCachesLine_returnsGpuAndTokens` |
| KV Caches zero values | `test_parse_kvCachesZero_returnsZeroValues` |
| Non-KV line | `test_parse_progressLine_returnsNilForKvParse` |
| HTTP 200 completion | `test_parse_http200Line_returnsHttpCompletion` |
| Non-completion HTTP | `test_parse_nonCompletionLine_returnsNil` |
| Ignored lines (×5) | `test_parse_ignoredLine_<type>_returnsNil` |
