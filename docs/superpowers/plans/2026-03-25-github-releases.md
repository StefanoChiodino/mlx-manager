# GitHub Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a GitHub Actions workflow that builds, bundles, signs, and publishes a DMG release whenever a `v*` tag is pushed.

**Architecture:** Single workflow file `.github/workflows/release.yml`. One job on `macos-15`, triggered by tag push. Inlines the bundle logic from the Makefile (minus the `/Applications` write lines), creates a drag-and-drop DMG via `hdiutil`, and publishes via `softprops/action-gh-release@v2`.

**Tech Stack:** GitHub Actions, Swift Package Manager, `hdiutil`, `codesign`, `softprops/action-gh-release@v2`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `.github/workflows/release.yml` | Create | Full release pipeline: build → bundle → sign → DMG → publish |

No other files change.

---

### Task 1: Create the workflow file

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the `.github/workflows/` directory and write the workflow file**

```bash
mkdir -p .github/workflows
```

Then create `.github/workflows/release.yml` with this exact content:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-15

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build
        run: swift build -c release

      - name: Bundle
        run: |
          mkdir -p build/MLXManager.app/Contents/MacOS build/MLXManager.app/Contents/Resources
          cp .build/release/MLXManagerApp build/MLXManager.app/Contents/MacOS/MLXManager
          cp Resources/Info.plist build/MLXManager.app/Contents/Info.plist
          iconutil -c icns Resources/AppIcon.iconset -o build/MLXManager.app/Contents/Resources/AppIcon.icns
          cp Sources/MLXManagerApp/presets.yaml build/MLXManager.app/Contents/Resources/presets.yaml
          cp Resources/LaunchAgent.plist build/MLXManager.app/Contents/Resources/LaunchAgent.plist

      - name: Sign
        run: codesign --force --deep -s - build/MLXManager.app

      - name: Create DMG
        run: |
          mkdir dmg-staging
          cp -r build/MLXManager.app dmg-staging/
          ln -s /Applications dmg-staging/Applications
          hdiutil create -volname MLXManager \
            -srcfolder dmg-staging \
            -ov -format UDZO \
            "MLXManager-${{ github.ref_name }}.dmg"

      - name: Publish release
        uses: softprops/action-gh-release@v2
        with:
          name: ${{ github.ref_name }}
          body: |
            MLXManager ${{ github.ref_name }}

            See the [README](https://github.com/${{ github.repository }}/blob/main/README.md) for installation and usage.
          files: MLXManager-${{ github.ref_name }}.dmg
```

- [ ] **Step 2: Verify the file was created correctly**

```bash
cat .github/workflows/release.yml
```

Expected: the full YAML above, no truncation.

- [ ] **Step 3: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add GitHub Actions release workflow for DMG publishing"
```

---

### Task 2: Push the repo to GitHub (if not already done) and verify the workflow runs

**Files:** none

> Skip this task if the repo is already on GitHub.

- [ ] **Step 1: Create the GitHub repo (if needed)**

```bash
gh repo create mlx-manager --private --source=. --push
```

If the repo already exists and has a remote:

```bash
git push -u origin main
```

- [ ] **Step 2: Tag and push to trigger the workflow**

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 3: Watch the workflow run**

```bash
gh run watch
```

Expected: the `release` job completes successfully (green).

- [ ] **Step 4: Verify the release was created**

```bash
gh release view v0.1.0
```

Expected: release named `v0.1.0`, with `MLXManager-v0.1.0.dmg` listed as an asset.

- [ ] **Step 5: Download and spot-check the DMG locally**

```bash
gh release download v0.1.0 --pattern "*.dmg" --dir /tmp
open /tmp/MLXManager-v0.1.0.dmg
```

Expected: DMG mounts, shows `MLXManager.app` and an `Applications` symlink. Drag-and-drop to Applications works.
