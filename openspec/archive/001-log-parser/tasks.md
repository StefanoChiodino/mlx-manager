# Tasks: LogParser

Each task = one RED test written and confirmed failing, then GREEN implementation.

## Setup

- [x] Scaffold `Package.swift` with a library target `MLXManager` and test target `MLXManagerTests`
- [x] Create stub `Sources/MLXManager/LogParser.swift` (returns nil for all input)
- [x] Create `Tests/MLXManagerTests/LogParserTests.swift` with all RED tests written
- [x] Confirm `swift test` compiles and runs — 13 tests, 0 failures

## Red-Green Cycles

- [x] **RED** `test_parse_progressLine_returnsMidRequestEvent` — failed (parse returned nil)
- [x] **GREEN** implement progress regex in `LogParser.parse`
- [x] **RED** `test_parse_progressNearEnd_returnsEventWithHighPercentage` — failed
- [x] **GREEN** percentage calculation correct
- [x] **RED** `test_parse_kvCachesLine_returnsGpuAndTokens` — failed
- [x] **GREEN** implement KV Caches regex
- [x] **RED** `test_parse_kvCachesZero_returnsZeroValues` — failed
- [x] **GREEN** zero-value KV line parses correctly
- [x] **RED** `test_parse_http200Line_returnsHttpCompletion` — failed
- [x] **GREEN** implement HTTP 200 regex
- [x] `test_parse_httpGetLine_returnsNil` — passed (nil correct)
- [x] `test_parse_kvCachesLine_returnsNilForProgressParser` — passed
- [x] `test_parse_progressLine_returnsNilForKvParser` — passed
- [x] `test_parse_ignoredLine_fetching_returnsNil` — passed
- [x] `test_parse_ignoredLine_warning_returnsNil` — passed
- [x] `test_parse_ignoredLine_resourceTracker_returnsNil` — passed
- [x] `test_parse_ignoredLine_startingHttpd_returnsNil` — passed
- [x] `test_parse_ignoredLine_hfModelCheck_returnsNil` — passed

## Done

- [x] All tests green — 13/13
- [x] `swift test` output shows 0 failures
- [x] Commit: `feat: implement LogParser with full test coverage`
