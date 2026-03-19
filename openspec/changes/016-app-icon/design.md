# App Icon - Technical Design

## Current State

`Info.plist` contains:
```xml
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>LSUIElement</key>
<true/>
```

Missing `CFBundleIconFile` key.

## Solution

Add `CFBundleIconFile` key to `Info.plist` to reference `AppIcon.icns`:

```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```

Note: The value should be the filename without extension (`AppIcon.icns` → `AppIcon`).

### Code Change

In `Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MLXManager</string>
    <key>CFBundleIdentifier</key>
    <string>com.stefano.mlx-manager</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>MLXManager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

## Implementation

1. Add `CFBundleIconFile` key to `Resources/Info.plist`
2. Rebuild and install app

## Testing

- Launch app, verify icon appears in menu bar
- Check icon in Mission Control
- Check icon in Alt-Tab switcher
