# Design: 009-progress-arc

## New type: StatusBarDisplayState

Replaces the string-based `updateTitle(_:)` protocol method. Lives in the MLXManager
layer (no AppKit dependency).

```swift
public enum StatusBarDisplayState: Equatable {
    case offline                          // hollow circle, no text
    case idle                             // filled green circle, no text
    case processing(fraction: Double)     // arc filled to fraction [0,1], "N%" label
}
```

`StatusBarController` computes this from `ServerState` and passes it to the view.

---

## Protocol change

```swift
public protocol StatusBarViewProtocol: AnyObject {
    func updateState(_ state: StatusBarDisplayState)
    func buildMenu(items: [StatusBarMenuItem])
}
```

`updateTitle(_:)` is removed. All callers (`serverDidStart`, `serverDidStop`, `update`)
switch to `updateState(_:)`.

---

## ArcProgressView (App layer)

```swift
final class ArcProgressView: NSView {
    var displayState: StatusBarDisplayState = .offline { didSet { needsDisplay = true } }
}
```

### Layout

Total width = arc diameter + gap + label width (only when processing).

- Arc diameter: 14 pt (fits 22 pt status bar height with 4 pt top/bottom padding)
- Gap between arc and label: 4 pt
- Label: system font size 11 pt, monospaced digits, right-aligned, min width for "100%"

The view resizes itself via `intrinsicContentSize` so the `NSStatusItem` width adjusts
automatically.

### Drawing (drawRect)

**Offline:**
- Stroke a full circle, `NSColor.tertiaryLabelColor`, line width 1.5

**Idle:**
- Fill a full circle, `NSColor.systemGreen`

**Processing(fraction):**
- Stroke background circle: `NSColor.tertiaryLabelColor`, line width 2, full 360°
- Stroke foreground arc: `NSColor.controlAccentColor`, line width 2,
  clockwise from 12 o'clock (−π/2) by `fraction * 2π`
- Draw percentage label: `"\(Int((fraction * 100).rounded()))%"`,
  `NSColor.labelColor`, 11 pt monospaced

### Wiring into NSStatusItem

`StatusBarView` creates one `ArcProgressView`, sets `statusItem.button?.image = nil`,
adds the arc view as a subview of `statusItem.button` and pins it with Auto Layout.

---

## StatusBarController changes

- Remove `progressBar(fraction:)`, `pieGlyph(fraction:)`, `progressTitle(fraction:settings:)`
- Remove `settings: AppSettings` parameter from `update(state:settings:)` — settings no
  longer affects rendering style
- `serverDidStart()` → `view.updateState(.idle)`
- `serverDidStop()` → `view.updateState(.offline)`
- `update(state:)`:
  - `.offline` → `view.updateState(.offline)`
  - `.idle` → `view.updateState(.idle)`
  - `.processing` → `view.updateState(.processing(fraction: progress.current / progress.total))`

---

## AppSettings changes

- Remove `progressStyle: ProgressStyle` and `ProgressStyle` enum entirely
- `AppSettings` retains only `ramGraphEnabled` and `ramPollInterval`

---

## Files changed

| File | Change |
|------|--------|
| `Sources/MLXManager/StatusBarController.swift` | updateState protocol; remove string rendering; remove settings param from update |
| `Sources/MLXManager/AppSettings.swift` | Remove ProgressStyle; remove progressStyle field |
| `Sources/MLXManagerApp/StatusBarView.swift` | Implement ArcProgressView; wire into button |
| `Tests/MLXManagerTests/StatusBarControllerTests.swift` | Update assertions to use displayState |
| `Tests/MLXManagerTests/StatusBarControllerNewTests.swift` | Remove progressStyle tests |
| `Tests/MLXManagerTests/AppSettingsTests.swift` | Remove progressStyle round-trip test |

---

## What is NOT changed

- `rebuildMenu` logic — menus are unchanged
- `StatusBarController` constructor signature — unchanged
- All window controllers — unchanged
- All other tests — unchanged
