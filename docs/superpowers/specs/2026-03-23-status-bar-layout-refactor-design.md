# Status Bar Layout Refactor — Design Spec

**Date:** 2026-03-23

## Problem

`StatusBarView` renders the arc icon and log line text using two independent mechanisms that don't know about each other:

- `ArcProgressView` is an `NSView` subview positioned with Auto Layout
- The log line is set via `button.title` (a plain `String`)

AppKit renders these into the same button frame without coordination. The code works around this by counting spaces to pad the title string past the icon — a heuristic that breaks under font scaling, appearance changes, and minor layout shifts. This is why the overlap recurs every time it is "fixed".

## Goal

Replace the space-counting hack with proper Auto Layout by retiring `button.title` and adding a dedicated `NSTextField` subview for the log line.

## Scope

Single file: `Sources/MLXManagerApp/StatusBarView.swift`. No other files change.

## Design

### Layout

Two subviews inside the `NSStatusItem` button, both with `translatesAutoresizingMaskIntoConstraints = false`:

| Subview | Type | Role |
|---------|------|------|
| `arcView` | `ArcProgressView` | Existing arc icon — left-anchored |
| `logLabel` | `NSTextField` | Log line text — right of arc |

Auto Layout constraints:
- `arcView.leadingAnchor` = `button.leadingAnchor + pad`
- `arcView.centerYAnchor` = `button.centerYAnchor`
- `logLabel.leadingAnchor` = `arcView.trailingAnchor + pad`
- `logLabel.trailingAnchor` = `button.trailingAnchor - pad`
- `logLabel.centerYAnchor` = `button.centerYAnchor`

Where `pad: CGFloat = 4` is a single named constant used in both the constraints and the `statusItem.length` formula below.

The existing `arcView.trailingAnchor` constraint is **removed**. The arc's width is driven solely by `ArcProgressView.intrinsicContentSize` (which returns a fixed width), so no explicit width constraint is needed.

### `logLabel` configuration

```swift
logLabel.isEditable = false
logLabel.isBordered = false
logLabel.drawsBackground = false
logLabel.translatesAutoresizingMaskIntoConstraints = false
logLabel.font = NSFont.menuBarFont(ofSize: 0)
logLabel.textColor = NSColor.labelColor   // adaptive — works in light and dark mode
logLabel.lineBreakMode = .byTruncatingTail
logLabel.cell?.truncatesLastVisibleLine = true
logLabel.stringValue = ""
logLabel.isHidden = true
```

`logLabel` uses `NSColor.labelColor` (adaptive) for the same reason all other text in `StatusBarView` does — this was explicitly chosen to handle appearance changes, which is also one of the causes of prior overlap bugs.

### `updateLogLine(_ line: String?)` behaviour

Must be called from, or dispatched to, the main thread (consistent with existing implementation).

| Input | Action |
|-------|--------|
| `line != nil` | Set `logLabel.stringValue = line`, unhide `logLabel`, set `statusItem.length` (see below) |
| `line == nil` | Set `logLabel.stringValue = ""`, hide `logLabel`, set `statusItem.length = NSStatusItem.variableLength` |

**Width calculation** when showing a log line (no max-width cap — the button expands to fit, truncation is a visual safety net for unexpectedly long strings):

```swift
let arcWidth = arcView.intrinsicContentSize.width
let font = logLabel.font ?? NSFont.menuBarFont(ofSize: 0)
let textWidth = (line as NSString).size(withAttributes: [.font: font]).width
statusItem.length = pad + arcWidth + pad + textWidth + pad
```

`pad` is the same constant used in the Auto Layout constraints. Keeping them in sync ensures the label is never clipped by `statusItem.length` and never leaves dead space.

When `logLabel` is hidden its `stringValue` is `""`, which collapses its intrinsic content width to zero. Combined with `statusItem.length = NSStatusItem.variableLength`, no stale width influences the layout.

### What does not change

- `ArcProgressView` — zero modifications to drawing code
- `StatusBarController`, `StatusBarDisplayState`
- Menu building (`buildMenu`)
- Popover methods (`showRAMGraphView`, `showHistoryView`, `showLogView`)
- All other source files

## Testing

`StatusBarView` is a UI-only class with no XCTest coverage (requires a running app). Verification is manual:

1. Build and run
2. No log line (idle/offline): confirm status bar shows arc icon only, no extra space
3. Short log line (e.g. `"Loading…"`): confirm arc and text appear side by side with no overlap
4. Long log line (e.g. a 100-character string): confirm the label truncates with an ellipsis and does not overflow the screen edge
5. Stop the server: confirm log line disappears and status bar collapses back to icon-only width
6. Cycle through offline / idle / processing states both with and without a log line — confirm arc renders correctly in all states
7. Toggle macOS appearance (light ↔ dark): confirm text colour adapts correctly and no overlap appears
