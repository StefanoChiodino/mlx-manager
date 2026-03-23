# Status Bar Layout Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire `button.title` log line text and replace it with an `NSTextField` subview, so Arc icon and log text are managed by Auto Layout and never overlap.

**Architecture:** Add a `logLabel: NSTextField` subview to the status bar button alongside the existing `ArcProgressView`. Auto Layout pins them side-by-side using a shared `pad` constant. `updateLogLine` sets the label text and resizes `statusItem.length` using the same constant — no space-counting heuristics.

**Tech Stack:** Swift, AppKit, XCTest (no new test file — UI-only class verified by build + manual run)

---

### Task 1: Remove the trailing constraint from `arcView` and add `logLabel` subview

This task restructures `StatusBarView.init()` — replacing the old three-constraint layout (lead, centreY, trail) with the new four-constraint layout (arcView: lead + centreY; logLabel: lead + centreY + trail).

**Files:**
- Modify: `Sources/MLXManagerApp/StatusBarView.swift:119-139` (the `init()` block)

There are no XCTest unit tests for `StatusBarView` — it requires a running macOS app. The "test" here is a build + visual verification.

- [ ] **Step 1: Open `StatusBarView.swift` and read the `init()` block**

  Confirm the current constraints at lines ~133-137:
  ```swift
  NSLayoutConstraint.activate([
      arcView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      arcView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
      arcView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
  ])
  ```
  The `trailingAnchor` constraint is what causes the arc to be stretched across the full button width, fighting with the title text.

- [ ] **Step 2: Add `logLabel` as a stored property**

  Add this line alongside the existing `private let arcView: ArcProgressView` declaration:
  ```swift
  private let logLabel: NSTextField
  ```

- [ ] **Step 3: Replace `init()` with the new two-subview layout**

  Replace the entire `init()` body with:
  ```swift
  init() {
      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      arcView = ArcProgressView()
      logLabel = NSTextField(labelWithString: "")

      logLabel.isEditable = false
      logLabel.isBordered = false
      logLabel.drawsBackground = false
      logLabel.font = NSFont.menuBarFont(ofSize: 0)
      logLabel.textColor = NSColor.labelColor
      logLabel.lineBreakMode = .byTruncatingTail
      logLabel.cell?.truncatesLastVisibleLine = true
      logLabel.isHidden = true

      if let button = statusItem.button {
          button.title = ""
          button.image = nil

          arcView.translatesAutoresizingMaskIntoConstraints = false
          logLabel.translatesAutoresizingMaskIntoConstraints = false
          button.addSubview(arcView)
          button.addSubview(logLabel)

          let pad: CGFloat = 4
          NSLayoutConstraint.activate([
              arcView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: pad),
              arcView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
              logLabel.leadingAnchor.constraint(equalTo: arcView.trailingAnchor, constant: pad),
              logLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -pad),
              logLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
          ])
      }
  }
  ```

  Also add `logLabel` as a stored property alongside `arcView`:
  ```swift
  private let logLabel: NSTextField
  ```

- [ ] **Step 4: Build to confirm no compile errors**

  ```bash
  swift build 2>&1 | grep -E "error:|warning:" | head -20
  ```
  Expected: no errors. Warnings about unused variables are fine; errors are not.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/MLXManagerApp/StatusBarView.swift
  git commit -m "refactor: add logLabel NSTextField subview to status bar button"
  ```

---

### Task 2: Rewrite `updateLogLine` to use `logLabel` instead of `button.title`

**Files:**
- Modify: `Sources/MLXManagerApp/StatusBarView.swift:234-252` (the `updateLogLine` method)

- [ ] **Step 1: Read the current `updateLogLine` implementation**

  Current code at lines ~234-252:
  ```swift
  func updateLogLine(_ line: String?) {
      DispatchQueue.main.async { [weak self] in
          guard let self, let button = self.statusItem.button else { return }
          if let line {
              let arcWidth = self.arcView.intrinsicContentSize.width
              let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
              let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
              let spacesNeeded = Int(ceil((arcWidth + 6) / spaceWidth))
              let padding = String(repeating: " ", count: spacesNeeded)
              button.title = padding + line
              let textWidth = (button.title as NSString).size(withAttributes: [.font: font]).width
              self.statusItem.length = textWidth + 8
          } else {
              button.title = ""
              self.statusItem.length = NSStatusItem.variableLength
          }
      }
  }
  ```
  This is the entire space-counting hack to replace.

- [ ] **Step 2: Replace `updateLogLine` with the new implementation**

  ```swift
  func updateLogLine(_ line: String?) {
      DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          let pad: CGFloat = 4
          if let line {
              self.logLabel.stringValue = line
              self.logLabel.isHidden = false
              let arcWidth = self.arcView.intrinsicContentSize.width
              let font = self.logLabel.font ?? NSFont.menuBarFont(ofSize: 0)
              let textWidth = (line as NSString).size(withAttributes: [.font: font]).width
              self.statusItem.length = pad + arcWidth + pad + textWidth + pad
          } else {
              self.logLabel.stringValue = ""
              self.logLabel.isHidden = true
              self.statusItem.length = NSStatusItem.variableLength
          }
      }
  }
  ```

  Note: `pad` must match the constant used in the Auto Layout constraints in Task 1. Both are `4`. If one ever changes, the other must too.

- [ ] **Step 3: Build to confirm no compile errors**

  ```bash
  swift build 2>&1 | grep -E "error:|warning:" | head -20
  ```
  Expected: no errors.

- [ ] **Step 4: Commit**

  ```bash
  git add Sources/MLXManagerApp/StatusBarView.swift
  git commit -m "fix: replace button.title space-padding with NSTextField subview for log line"
  ```

---

### Task 3: Build the app and manually verify

**Files:** None — verification only.

- [ ] **Step 1: Build the full app**

  ```bash
  make build 2>&1 | tail -20
  ```
  Or if no Makefile target:
  ```bash
  swift build -c release 2>&1 | tail -20
  ```
  Expected: `Build complete!`

- [ ] **Step 2: Run the app and verify — no log line**

  Launch the app. In the menu bar:
  - Confirm the arc icon appears (circle with M)
  - Confirm no extra space or ghost text to the right of it
  - Confirm the status bar item width is compact (icon-only)

- [ ] **Step 3: Trigger a log line and verify — with log line**

  Start the MLX server from the app. Once a log line appears in the status bar:
  - Confirm arc icon is on the left
  - Confirm log text is immediately to the right, no gap or overlap
  - Confirm both are visible simultaneously

- [ ] **Step 4: Cycle through all arc states**

  With and without a log line visible, use the app to produce offline, idle, and processing states (stop server → offline; start server idle → idle; trigger a request → processing). Confirm arc renders correctly in all three states alongside the log text.

- [ ] **Step 5: Toggle light/dark appearance**

  In System Settings → Appearance, switch between Light and Dark. Confirm the log text colour adapts (uses `NSColor.labelColor`) and no overlap appears in either mode.

- [ ] **Step 6: Test with a long string (optional, dev console)**

  If you can inject a long log line (e.g. via a test preset or by temporarily hardcoding a long string in `StatusBarController`), confirm truncation with ellipsis rather than overflow.

- [ ] **Step 5: Stop the server and verify collapse**

  Stop the server. Confirm:
  - Log line disappears
  - Status bar item shrinks back to icon-only width

- [ ] **Step 6: Commit if any minor fixes were needed**

  If manual testing revealed any small tweaks (e.g. padding adjustment), apply them and commit:
  ```bash
  git add Sources/MLXManagerApp/StatusBarView.swift
  git commit -m "fix: adjust status bar log line layout after manual verification"
  ```
  If no changes needed, skip this step.
