# App Icon - Proposal

## Summary

The application icon is not showing in the menu bar or in the application switcher. The icon file exists in the app bundle but is not being referenced by Info.plist.

## Impact

- Users cannot identify the app by icon in menu bar
- App appears without icon in Mission Control and Dock
- Poor visual identity

## Root Cause

`Info.plist` is missing the `CFBundleIconFile` key that tells macOS to use the `AppIcon.icns` file from the Resources folder.

## Acceptance Criteria

- App icon appears in menu bar
- App icon appears in Mission Control
- App icon appears in application switcher (Alt-Tab)
