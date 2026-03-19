# Settings Window Visibility - Technical Design

## Current Behavior

In `AppDelegate.showSettings()`:

```swift
settingsWindowController?.showWindow(nil)
settingsWindowController?.window?.makeKeyAndOrderFront(nil)
```

This shows the window but doesn't bring it to front properly. The window is created but goes to the back.

## Root Cause

`showWindow()` creates the window if needed, and `makeKeyAndOrderFront()` makes it key and orders it front, but without `NSApp.activate(ignoringOtherApps: true)`, the window doesn't become the frontmost window and isn't shown in Alt-Tab.

## Solution

Call `NSApp.activate(ignoringOtherApps: true)` after showing the window. This tells macOS to activate our application and bring its windows to the front.

### Code Change

In `AppDelegate.swift` `showSettings()` method (lines 231-258):

```swift
private func showSettings(presets: [ServerConfig]) {
    if settingsWindowController == nil {
        settingsWindowController = SettingsWindowController(presets: presets, settings: settings)
        settingsWindowController?.onSave = { [weak self] newPresets, newSettings in
            // ... existing code
        }
    }
    settingsWindowController?.showWindow(nil)
    settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)  // ADD THIS LINE
}
```

### Apply to All Windows

Same fix needed for:
- `showLog()` - LogWindowController
- `showHistory()` - HistoryWindowController (now using companion view)
- `showRAMGraph()` - RAMGraphWindowController (now using companion view)

## Implementation

1. Add `NSApp.activate(ignoringOtherApps: true)` to `showSettings()`
2. Add `NSApp.activate(ignoringOtherApps: true)` to `showLog()`
3. Verify log window and history window behave correctly

## Testing

- Open settings, verify window appears immediately and is visible
- Press Alt-Tab, verify settings window appears in switcher
- Open settings twice, verify second click brings window to front
- Same tests for log window
