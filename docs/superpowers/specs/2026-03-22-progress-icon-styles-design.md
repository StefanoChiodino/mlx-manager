# Progress Icon Styles

## Summary

Three status bar icon styles are defined for MLX Manager. The arc-ring style (Style A) is already built. This cycle adds Style B (continuous M fill) and wires it to a new `progressIconStyle` setting. Style C is specced for future reference only.

## Styles

### A — Arc ring + M (already implemented)

A thick circular arc sweeps clockwise around a bold "M". The M is always visible; the arc conveys progress.

| State | Rendering |
|---|---|
| Offline | Muted ring (`tertiaryLabelColor` 50% opacity) + muted M |
| Idle | Green ring (`systemGreen`) + `labelColor` M |
| Processing | Dim track ring + `controlAccentColor` arc sweeping from 12 o'clock + `labelColor` M |

### B — Continuous M fill (implement this cycle)

The letter M is drawn as a single continuous polyline path. Progress "draws" the stroke from start to finish using a dash pattern. The path traces: bottom-left → top-left → V-dip → top-right → bottom-right.

| State | Rendering |
|---|---|
| Offline | Full M path in `tertiaryLabelColor` 50% opacity |
| Idle | Full M path in `systemGreen` |
| Processing | Dim full M path (`tertiaryLabelColor` 40% opacity) + `controlAccentColor` partial path, proportional to `fraction` |

**Continuous fill technique (AppKit):**
Use `NSBezierPath` with `setLineDash(_:count:phase:)`. Set a single dash of length `totalPathLength` with phase `totalPathLength * (1 - fraction)`. This draws exactly `fraction` of the path from the start point. There is no `CGPath.length` API — total path length must be computed manually by summing the four segment lengths.

**M path geometry** — coordinates are relative to a local `mRect` (a square rect sized to `diameter`, positioned inside `bounds` the same way `arcRect` is positioned in the existing arc branch):

| Point | Position within `mRect` |
|---|---|
| Start | bottom-left: `(mRect.minX, mRect.minY)` |
| Top-left | `(mRect.minX, mRect.maxY)` |
| V-dip | `(mRect.midX, mRect.minY + mRect.height * 0.58)` |
| Top-right | `(mRect.maxX, mRect.maxY)` |
| End | bottom-right: `(mRect.maxX, mRect.minY)` |

*Note: AppKit's y-axis increases upward, so `mRect.minY` is the bottom edge and `mRect.maxY` is the top edge.*

Stroke width: ~2pt (slightly thinner than the arc's 2.5pt to keep the M legible at small size — tune visually). Line cap: `.round`. Line join: `.round`.

**Total path length:** sum of the four Euclidean segment lengths:
- Left leg: `mRect.height`
- Left diagonal: `sqrt((mRect.midX - mRect.minX)² + (mRect.height * 0.42)²)` — distance from top-left to V-dip
- Right diagonal: same as left diagonal (symmetric)
- Right leg: `mRect.height`

Compute once as a constant (or lazy property) inside the M-fill drawing branch.

### C — MLX text flood fill (future, not implemented this cycle)

The text "MLX" is displayed. During processing a left-to-right clip region reveals `controlAccentColor` beneath a dim base layer. Wider than A or B.

| State | Rendering |
|---|---|
| Offline | "MLX" in `tertiaryLabelColor` 50% opacity |
| Idle | "MLX" in `systemGreen` |
| Processing | Dim "MLX" base + `controlAccentColor` "MLX" clipped to `NSRect(x: 0, y: 0, width: totalWidth * fraction, height: height)` |

*Not implemented this cycle.*

---

## Settings

### `ProgressIconStyle` enum

Add to `AppSettings.swift` (alongside the `AppSettings` struct, not nested inside it):

```swift
public enum ProgressIconStyle: String, CaseIterable, Codable {
    case arcRing   // Style A
    case mFill     // Style B
    case mlxFill   // Style C (future)
}
```

### `AppSettings` changes

1. Add `public var progressIconStyle: ProgressIconStyle = .arcRing`
2. Add `.progressIconStyle` to `CodingKeys`
3. In the hand-written `init(from decoder:)`, add:
   ```swift
   progressIconStyle = try container.decodeIfPresent(ProgressIconStyle.self, forKey: .progressIconStyle) ?? .arcRing
   ```
   Note: the existing four fields in `init(from:)` use `container.decode(...)` (required keys). The new field deliberately uses `decodeIfPresent` so that existing settings files lacking the key decode cleanly and fall back to `.arcRing` — preserving the current behaviour for existing users. These two approaches coexist intentionally.

**Default is `.arcRing`** — existing users who upgrade will continue to see the arc-ring icon unchanged. They can switch to M-fill in Settings.

**Persistence:** Settings are saved to `~/.config/mlx-manager/settings.json` via `JSONEncoder`/`JSONDecoder` in `AppDelegate`. No `UserDefaults` is used.

### Wiring the style to the view

`AppDelegate.onSave` already rebuilds `StatusBarView` and `StatusBarController` from scratch on every save. The style reaches the view as follows:

1. `StatusBarView.init` gains a `style: ProgressIconStyle` parameter (default `.mFill`)
2. `StatusBarView` passes it to `ArcProgressView` via a new `style` property setter
3. In `AppDelegate`, both the initial `StatusBarView()` construction (line ~35) and the `onSave` rebuild (line ~232) pass `settings.progressIconStyle`

`ArcProgressView` does not observe settings itself — it is a passive view driven by `displayState` and `style`. The `style` property should follow the same `didSet { needsDisplay = true }` pattern as `displayState`, for consistency (even though in practice style is only set once at init time).

### Settings window

In `SettingsWindowController`, under the General tab:

- Add `private let iconStylePopup = NSPopUpButton()`
- In `buildGeneralView`: `buildGeneralView` uses `NSGridView(numberOfColumns: 2, rows: 3)` — change to `rows: 4`. Add the fourth row inline (same pattern as the existing three rows):
  ```swift
  let styleLabel = NSTextField(labelWithString: "Icon style:")
  grid.addRow(with: [styleLabel, iconStylePopup])   // or assign via cell(atColumnIndex:rowIndex:) at row 3
  ```
  Populate the popup with `["Arc Ring", "M Fill"]` and call `iconStylePopup.selectItem(at: draftSettings.progressIconStyle == .arcRing ? 0 : 1)` in `buildGeneralView` alongside the other control setup. There is no separate `populateGeneralTab` method — all General tab wiring is inline in `buildGeneralView`.
- In `saveTapped`:
  ```swift
  draftSettings.progressIconStyle = iconStylePopup.indexOfSelectedItem == 0 ? .arcRing : .mFill
  ```

---

## Scope — This Cycle

| File | Change |
|---|---|
| `AppSettings.swift` | Add `ProgressIconStyle` enum; add `progressIconStyle` property + `CodingKeys` entry + `decodeIfPresent` in custom decoder |
| `StatusBarView.swift` — `ArcProgressView` | Add `style: ProgressIconStyle` property; add M-fill drawing branch to `draw()`; existing arc branch unchanged |
| `StatusBarView.swift` — `StatusBarView` | Add `style` param to `init`; pass to `arcView.style` |
| `AppDelegate.swift` | Pass `settings.progressIconStyle` to both `StatusBarView` constructions |
| `SettingsWindowController.swift` | Add `iconStylePopup`; wire in `buildUI`, `populateGeneralTab`, `saveTapped` |
| `AppSettingsTests.swift` | Add: (1) round-trip test for `progressIconStyle`; (2) migration test — JSON without `progressIconStyle` key decodes with default `.mFill` |

### Not in scope

- Style C (MLX flood fill)
- `ArcProgressView` unit tests for rendering (verified visually, consistent with existing approach)
- `StatusBarViewProtocol` changes

---

## Unchanged

- `StatusBarDisplayState` enum
- `StatusBarController`
- `StatusBarViewProtocol`
- All log parsing, server management, process scanning code
