# Proposal: 009-progress-arc

## Problem

The current status bar indicator uses Unicode block glyphs (`▓▓▓░░░ 32%`). These are
a relic of the SwiftBar shell-script era. We are building a native AppKit application
and can draw anything we want. The block glyphs are low-resolution, visually crude,
and don't make use of any of the rendering capabilities available to us.

## Proposed Solution

Replace the glyph-based title string with a custom `NSView` rendered directly into the
`NSStatusItem` button. The view draws:

- A **circle arc** that fills clockwise from the top, representing request progress
  (0% = empty outline, 100% = fully filled)
- A **percentage label** to the right of the arc

All three server states use the same view with different parameters:

| State | Arc | Fill | Text |
|-------|-----|------|------|
| Offline | Outline circle | None | — |
| Idle | Filled circle | Green | — |
| Processing | Partial arc fill | Blue | `67%` |

The arc and percentage together form a compact, glanceable status indicator that looks
native and takes advantage of Core Graphics / AppKit rendering.

## What Changes

- `StatusBarView.swift` — replace `NSStatusItem.button?.title` approach with a custom
  `ArcProgressView: NSView` set as `statusItem.button?.subview` (or as the button's
  custom view via `statusItem.button`)
- `StatusBarViewProtocol` — replace `updateTitle(_:)` with `updateState(_: StatusBarDisplayState)`
  so the view receives typed state rather than a pre-rendered string
- `StatusBarController` — remove all string-rendering logic (`progressBar`, `pieGlyph`,
  `progressTitle`); instead pass `StatusBarDisplayState` directly to the view
- `AppSettings.progressStyle` — `.pie` and `.bar` options become obsolete; remove them
  (simplification — there is now one style: the arc)
- Tests that assert specific title strings updated to assert display state values

## Out of Scope

- Animation (smooth arc transition between progress updates) — can be added later
- Colour theming / dark-mode-specific colours — AppKit handles this automatically
- Showing KV cache values in the arc view — separate concern (addressed elsewhere)
