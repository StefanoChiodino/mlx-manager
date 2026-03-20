# Tasks: 009-progress-arc

## A. StatusBarDisplayState

- [x] **RED** `test_statusBarDisplayState_exists` — type exists
- [x] **GREEN** `StatusBarDisplayState` enum created in MLXManager layer

---

## B. StatusBarViewProtocol: updateState

- [x] **RED** `test_mockView_conformsToUpdatedProtocol` — `updateState(_:)` exists on protocol
- [x] **GREEN** `updateState(_:)` in place; `StatusBarController` calls it

---

## C. StatusBarController: state-driven rendering

- [x] **RED** `test_statusBarController_offline_state` — controller calls `updateState(.offline)` on init
- [x] **GREEN** `serverDidStart/Stop` and `update(state:)` emit correct `StatusBarDisplayState`

- [x] **RED** `test_statusBarController_processing_fraction` — `.processing(fraction:)` matches progress ratio
- [x] **GREEN** `fraction = Double(current) / Double(total)` computed and passed through

- [x] (compile) `settings` param removed from `update(state:)`; callers fixed

---

## D. AppSettings: remove ProgressStyle

- [x] (compile) `ProgressStyle` enum and `progressStyle` field removed from `AppSettings`
- [x] `AppSettings` updated; `SettingsWindowController` fixed

---

## E. ArcProgressView + StatusBarView

- [x] `ArcProgressView: NSView` implemented with `displayState` property and `draw(_:)`
- [x] Wired into `StatusBarView` via `ArcProgressView` subview
- [x] `StatusBarView.updateState(_:)` sets `arcView.displayState`
- [x] `swift build` clean

---

## F. Fix up tests

- [x] `StatusBarControllerTests` updated with `displayState` checks
- [x] All tests green

---

## Done

- [x] All tests green
- [x] `swift build` clean

The status bar progress feature is fully implemented and tested.
