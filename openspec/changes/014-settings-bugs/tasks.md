# Settings Window Bugs - Implementation Tasks

- [x] **T1**: Fix settings window activation - Added `NSApp.activate(ignoringOtherApps: true)` to `showSettings()`
- [x] **T2**: Fix preset table layout - Added `envBox.heightAnchor.constraint(equalToConstant: 100)` to prevent overlap
- [x] **T3**: Add `showRAMGraphView(samples:)` to `StatusBarViewProtocol`
- [x] **T4**: Implement RAM graph view in `StatusBarView` using `NSPopover` with `contentViewController`
- [x] **T5**: Add `showHistoryView(records:)` to `StatusBarViewProtocol`
- [x] **T6**: Implement history view in `StatusBarView` using `NSPopover` with `contentViewController`
- [x] **T7**: Update `AppDelegate` to use companion views instead of floating windows
- [x] **T8**: Clean up unused window controller properties from `AppDelegate`

All tasks completed and build successful.
