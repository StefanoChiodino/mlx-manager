# Settings Window Bugs - Technical Design

## Issue 1: Settings Window Activation

**Current behavior:** `showWindow(nil)` + `makeKeyAndOrderFront(nil)` is called, but the window doesn't come to front when already open.

**Root cause:** The window is shown but not properly activated. macOS window activation requires calling `makeKeyAndOrderFront()` on the window's `NSWindow` object after calling `showWindow()`.

**Solution:** In `AppDelegate.showSettings()`:
- Check if window is already shown
- If shown, call `window?.makeKeyAndOrderFront(nil)` directly on the existing window
- Ensure `window.isReleasedWhenClosed = false` is set (already done)

## Issue 2: NSBox Layout Overlap

**Current behavior:** In `SettingsWindowController.buildPresetsView()`, the `envBox` (Set Up Environment NSBox) is constrained to the bottom of the container, but the `rowButtons` stack is also constrained to the bottom, causing overlap.

**Root cause:** The constraints don't account for the height of the NSBox when positioning the rowButtons.

**Solution:** Recalculate constraints in `buildPresetsView()`:
1. Set `envBox` to bottom with fixed height (e.g., 80pt)
2. Position `rowButtons` above `envBox` with proper spacing
3. Adjust `scrollView` bottom constraint to end at `rowButtons` top

```swift
NSLayoutConstraint.activate([
    scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
    scrollView.bottomAnchor.constraint(equalTo: rowButtons.topAnchor, constant: -4),
    
    rowButtons.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    rowButtons.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    rowButtons.bottomAnchor.constraint(equalTo: envBox.topAnchor, constant: -8),
    
    envBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    envBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    envBox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
    envBox.heightAnchor.constraint(equalToConstant: 90) // Fixed height
])
```

## Issue 3 & 4: RAM Graph and History as Companion Views

**Current behavior:** Both `RAMGraphWindowController` and `HistoryWindowController` are separate `NSWindowController` instances that create floating windows.

**Root cause:** Each window is created independently with `NSWindow` and shown via `showWindow()` + `makeKeyAndOrderFront()`.

**Solution:** Convert to embedded menu items with custom views:

1. **Create companion view classes:**
   - `RAMGraphView` - Already exists in `RAMGraphWindowController`
   - `HistoryChartView` - Already exists in `HistoryWindowController`

2. **Modify `StatusBarViewProtocol`:**
   - Add `showRAMGraphView(samples:)` method
   - Add `showHistoryView(records:)` method

3. **Implement in `StatusBarView`:**
   - Create `NSPopUpButton` or custom menu item with attached views
   - When clicked, display the graph/history view in a popover/menu below the status bar icon
   - Auto-close when clicking elsewhere

4. **Modify `AppDelegate`:**
   - Remove `RAMGraphWindowController` and `HistoryWindowController` instances
   - Call `statusBarController.showRAMGraphView(samples: ramSamples)` instead
   - Call `statusBarController.showHistoryView(records: requestHistory)` instead

5. **Update `StatusBarController`:**
   - Pass samples/records to the view methods
   - Handle view lifecycle (show/hide/close)

## Architecture Changes

```
Before:
AppDelegate → RAMGraphWindowController (floating NSWindow)
AppDelegate → HistoryWindowController (floating NSWindow)

After:
AppDelegate → StatusBarController
  → StatusBarView.showRAMGraphView(samples:) → Embedded RAMGraphView
  → StatusBarView.showHistoryView(records:) → Embedded HistoryChartView
```

## Implementation Steps

1. Fix settings window activation in `AppDelegate.showSettings()`
2. Fix preset table layout in `SettingsWindowController.buildPresetsView()`
3. Add `showRAMGraphView(samples:)` to `StatusBarViewProtocol`
4. Implement `showRAMGraphView(samples:)` in `StatusBarView` using popover
5. Add `showHistoryView(records:)` to `StatusBarViewProtocol`
6. Implement `showHistoryView(records:)` in `StatusBarView` using popover
7. Update `AppDelegate` to use new methods instead of window controllers
8. Clean up unused window controller code (optional)
