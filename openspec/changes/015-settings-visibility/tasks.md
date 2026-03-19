# Settings Window Visibility - Implementation Tasks

- [x] **T1**: Add `NSApp.activate(ignoringOtherApps: true)` to `showSettings()` in `AppDelegate.swift`
- [ ] **T2**: Add `NSApp.activate(ignoringOtherApps: true)` to `showLog()` in `AppDelegate.swift`
- [ ] **T3**: Verify log window appears in Alt-Tab switcher
- [ ] **T4**: Verify settings window appears in Alt-Tab switcher
- [ ] **T5**: Test opening settings multiple times - window should come to front each time

**Files to modify:**
- `Sources/MLXManagerApp/AppDelegate.swift` - lines 231-258 (showSettings), lines 205-211 (showLog)

**Current state:**
- T1 already implemented (line 257)
- T2-T5 remain to be implemented and tested
