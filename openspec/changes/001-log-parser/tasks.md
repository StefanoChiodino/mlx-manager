# Tasks: LogParser

Each task = one RED test written and confirmed failing, then GREEN implementation.

## Setup

- [x] Scaffold `Package.swift` with a library target `MLXManager` and test target `MLXManagerTests`
- [x] Create stub `Sources/MLXManager/LogParser.swift` (returns nil for all input)
- [x] Create `Tests/MLXManagerTests/LogParserTests.swift` with all RED tests written
- [ ] Confirm `swift test` compiles — **BLOCKED: Xcode not installed, XCTest unavailable**

## Red-Green Cycles

> All tests written. Pending Xcode installation to run.

- [ ] **RED** `test_parse_progressLine_returnsMidRequestEvent` — will fail (parse returns nil)
- [ ] **GREEN** implement progress regex in `LogParser.parse`
- [ ] **RED** `test_parse_progressNearEnd_returnsEventWithHighPercentage` — will fail
- [ ] **GREEN** confirm percentage calculation correct
- [ ] **RED** `test_parse_kvCachesLine_returnsGpuAndTokens` — will fail
- [ ] **GREEN** implement KV Caches regex
- [ ] **RED** `test_parse_kvCachesZero_returnsZeroValues` — will fail
- [ ] **GREEN** confirm zero-value KV line parses correctly
- [ ] **RED** `test_parse_http200Line_returnsHttpCompletion` — will fail
- [ ] **GREEN** implement HTTP 200 regex
- [ ] **RED** `test_parse_httpGetLine_returnsNil` — will pass (nil is correct)
- [ ] **RED** `test_parse_kvCachesLine_returnsNilForProgressParser` — will pass
- [ ] **RED** `test_parse_progressLine_returnsNilForKvParser` — will pass
- [ ] **RED** `test_parse_ignoredLine_fetching_returnsNil` — will pass
- [ ] **RED** `test_parse_ignoredLine_warning_returnsNil` — will pass
- [ ] **RED** `test_parse_ignoredLine_resourceTracker_returnsNil` — will pass
- [ ] **RED** `test_parse_ignoredLine_startingHttpd_returnsNil` — will pass
- [ ] **RED** `test_parse_ignoredLine_hfModelCheck_returnsNil` — will pass

## Done

- [ ] All tests green
- [ ] `swift test` output shows 0 failures
- [ ] Commit: `feat: implement LogParser with full test coverage`
