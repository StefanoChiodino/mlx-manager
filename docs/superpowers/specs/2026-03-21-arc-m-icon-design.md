# Arc + "M" Status Bar Icon

## Summary

Replace the current status bar icon (hollow circle / filled green dot / arc + percentage text) with a unified design: a thick arc ring with a bold "M" centered inside, across all three states. Remove the percentage text label — progress is communicated purely through the arc.

## Current Behaviour

| State | Rendering |
|---|---|
| Offline | Hollow circle outline, `tertiaryLabelColor`, stroke 1.5, full opacity |
| Idle | Filled solid green circle |
| Processing | Background track circle (stroke 2, 40% opacity) + foreground arc (`controlAccentColor`, stroke 2, round cap) + percentage text ("45%") to the right |

The intrinsic width expands during processing to accommodate the percentage label.

## New Behaviour

All three states share the same base shape: a thick arc ring with a bold "M" inside. The icon width is constant.

| State | Ring | M colour | Description |
|---|---|---|---|
| Offline | `tertiaryLabelColor`, 50% opacity, stroke ~2.5 | `tertiaryLabelColor` | Muted ring + muted M |
| Idle | `systemGreen`, full opacity, stroke ~2.5 | `labelColor` | Green ring signals server running |
| Processing | Track ring (`tertiaryLabelColor`, 40% opacity) + foreground arc `controlAccentColor`, stroke ~2.5, round cap | `labelColor` | Arc sweeps clockwise from 12 o'clock proportional to `fraction` |

### Removed

- Percentage text label — no `"45%"` beside the icon
- Variable intrinsic width — icon is fixed-size in all states

### Dimensions

- Circle diameter: 13pt (unchanged, fits 22pt menu bar)
- Ring stroke width: ~2.5pt
- "M" font: system font, ~8pt, heavy weight — rendered via `NSAttributedString.draw(at:)`
- Intrinsic width: constant `diameter + 4` in all states

Exact stroke width and font size values are approximate — to be refined during implementation for visual balance at 13pt.

## Scope

### Changed

- `ArcProgressView` in `StatusBarView.swift` — `draw(_:)` and `intrinsicContentSize` rewritten for all three states

### Unchanged

- `StatusBarDisplayState` enum — still `.offline`, `.idle`, `.processing(fraction:)`
- `StatusBarController` — still computes `fraction = current / total` from `ProgressInfo`
- `StatusBarViewProtocol` — no API changes
- `ServerState` / `LogParser` / `LogTailer` — untouched
- All existing non-rendering tests — state transitions, log parsing, etc.

## Progress Data Flow (for reference)

Log lines like `Prompt processing progress: 4096/41061` are parsed by `LogParser` into `.progress(current: 4096, total: 41061, percentage: 9.97)`. `ServerState` stores this as `ProgressInfo`. `StatusBarController` computes `fraction = Double(current) / Double(total)` and passes `.processing(fraction:)` to the view. The arc renders this fraction as a sweep angle.

Progress never reaches `current == total`. Completion is signalled by a KV Caches line or HTTP 200 response, which transitions state back to `.idle`.

## Testing

Existing unit tests for `StatusBarDisplayState`, `StatusBarController`, and `ServerState` remain valid — they test state transitions and fraction computation, not rendering.

The `ArcProgressView` rendering is AppKit drawing code (`draw(_:)` override) and is verified visually, not via unit tests. This matches the current approach.
