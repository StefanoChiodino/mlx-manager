# Settings Window Visibility - Proposal

## Summary

When the settings window (or any panel) is opened, it immediately goes to the back and becomes invisible. The user cannot see the window open. Alt-Tab does not show the window - it can only be found in Mission Control.

## Impact

- Users cannot see the settings window when it opens
- Window is inaccessible via normal window switching (Alt-Tab)
- Frustrating UX where window appears to "disappear" after opening
- Same issue likely affects log window and history window

## Root Cause

The window is being created and shown, but `makeKeyAndOrderFront()` is not bringing it to the front properly. macOS requires explicit activation of the application and the window to make it visible and accessible via window switching.

## Acceptance Criteria

- Settings window becomes visible immediately when opened
- Window appears in Alt-Tab switcher
- Window comes to front when clicked in menu
- Same behavior for log window and history window
- No need to use Mission Control to find windows
