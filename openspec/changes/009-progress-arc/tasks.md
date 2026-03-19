# Tasks: 009-progress-arc

## A. StatusBarDisplayState

- [ ] **RED** `test_statusBarDisplayState_exists` — type doesn't exist; fails to compile
- [ ] **GREEN** create `StatusBarDisplayState` enum in MLXManager layer

---

## B. StatusBarViewProtocol: updateState

- [ ] **RED** `test_mockView_conformsToUpdatedProtocol` — `updateState(_:)` doesn't exist on
  protocol; MockStatusBarView fails to compile
- [ ] **GREEN** replace `updateTitle(_:)` with `updateState(_:)` in protocol; update
  `StatusBarController` to call `updateState`; update `MockStatusBarView` in tests

---

## C. StatusBarController: state-driven rendering

- [ ] **RED** `test_statusBarController_offline_state` — controller calls `updateState(.offline)` on init
- [ ] **GREEN** wire `serverDidStart/Stop` and `update(state:)` to emit correct `StatusBarDisplayState`

- [ ] **RED** `test_statusBarController_processing_fraction` — `.processing(fraction:)` value matches progress ratio
- [ ] **GREEN** compute `fraction = Double(current) / Double(total)` and pass through

- [ ] **RED** (compile) remove `settings` param from `update(state:settings:)` — callers break
- [ ] **GREEN** rename to `update(state:)`; fix `AppDelegate` call site

---

## D. AppSettings: remove ProgressStyle

- [ ] **RED** (compile) remove `ProgressStyle` enum and `progressStyle` field from `AppSettings`
- [ ] **GREEN** delete enum; update `AppSettings`; fix `SettingsWindowController` (remove style popup)
- [ ] Update `AppSettingsTests` to remove progressStyle round-trip test

---

## E. ArcProgressView + StatusBarView (build-only, no unit tests)

- [ ] Implement `ArcProgressView: NSView` with `displayState` property and `draw(_:)`
- [ ] Wire into `StatusBarView`: replace title-string approach with `ArcProgressView` subview
- [ ] Implement `StatusBarView.updateState(_:)` — sets `arcView.displayState`
- [ ] `swift build` clean

---

## F. Fix up tests

- [ ] Update `StatusBarControllerTests` — replace title-string assertions with `displayState` checks
  via an updated `MockStatusBarView` that captures `lastState: StatusBarDisplayState?`
- [ ] Remove pie/bar progressStyle tests from `StatusBarControllerNewTests`
- [ ] `swift test` all green

---

## Done

- [ ] All tests green
- [ ] `swift build` clean
