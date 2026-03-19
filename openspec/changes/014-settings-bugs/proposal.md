# Settings Window Bugs - Proposal

## Summary

Fix four UI/UX issues with the settings window and companion views:

1. **Settings window doesn't come to front** - When the settings window is already open and the user clicks "Settings…" in the status bar menu, the window doesn't come to the front. Alt-Tab doesn't show it.

2. **NSBox covers preset table buttons** - The "Set Up Environment" NSBox is positioned over the preset table's row buttons (+/−), making them inaccessible.

3. **RAM graph is a floating window** - The RAM graph should be a companion view embedded in the status bar menu area, not a separate floating window.

4. **History window is a floating window** - The request history should be a companion view, not a separate window.

## Impact

- Users cannot easily bring the settings window to front when already open
- Users cannot access preset management buttons due to layout overlap
- RAM graph and history windows waste screen space and clutter the UI
- Better UX by integrating these views into the status bar menu

## Acceptance Criteria

- Settings window properly activates when clicked while already open
- Preset table buttons are fully visible and accessible
- RAM graph is embedded in the status bar menu as a dropdown view
- History is embedded in the status bar menu as a dropdown view
- All existing functionality preserved
