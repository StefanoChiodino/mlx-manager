---
name: GitHub Releases via Git Tags
description: Automated GitHub Release pipeline triggered by git tags, producing a DMG with the MLXManager.app bundle
type: project
---

# GitHub Releases via Git Tags

## Overview

A single GitHub Actions workflow publishes a new GitHub Release whenever a version tag (e.g. `v1.0.0`) is pushed. The release asset is a `.dmg` containing the ad-hoc-signed `MLXManager.app` with a symlink to `/Applications` for drag-and-drop installation.

## Trigger

```yaml
on:
  push:
    tags:
      - 'v*'
```

Push a tag → release. No manual dispatch. No branch conditions.

## Permissions

The workflow requires write access to create the GitHub Release and upload assets:

```yaml
permissions:
  contents: write
```

Without this, `softprops/action-gh-release@v2` fails with 403 on repos where the default `GITHUB_TOKEN` is read-only (the current GitHub default for new repos).

## Runner

`macos-15` — pinned explicitly (not `macos-latest`) for build reproducibility. Apple Silicon runner required because `swift build` targets Apple Silicon. `macos-15` is currently the only Apple Silicon runner available on GitHub-hosted infrastructure.

## Job: `release`

Single job, no artifact handoff between jobs.

### Steps

1. **Checkout** — `actions/checkout@v4`
2. **Build** — `swift build -c release`
   - Produces `.build/release/MLXManagerApp`
3. **Bundle** — Inline shell equivalent to the relevant parts of `make bundle`. The Makefile contains two lines that write directly to `/Applications` (for local install convenience) — these are omitted in CI:
   ```sh
   mkdir -p build/MLXManager.app/Contents/MacOS build/MLXManager.app/Contents/Resources
   cp .build/release/MLXManagerApp build/MLXManager.app/Contents/MacOS/MLXManager
   cp Resources/Info.plist build/MLXManager.app/Contents/Info.plist
   iconutil -c icns Resources/AppIcon.iconset -o build/MLXManager.app/Contents/Resources/AppIcon.icns
   cp Sources/MLXManagerApp/presets.yaml build/MLXManager.app/Contents/Resources/presets.yaml
   cp Resources/LaunchAgent.plist build/MLXManager.app/Contents/Resources/LaunchAgent.plist
   ```
   Note: `iconutil` assumes `Resources/AppIcon.iconset/` is a valid iconset. If `iconutil` fails on the CI runner, the iconset must be fixed before the release pipeline will work.
4. **Sign** — `codesign --force --deep -s - build/MLXManager.app` (ad-hoc)
5. **Create DMG** — Staging directory with a relative `/Applications` symlink, then `hdiutil create`:
   ```sh
   mkdir dmg-staging
   cp -r build/MLXManager.app dmg-staging/
   ln -s /Applications dmg-staging/Applications
   hdiutil create -volname MLXManager \
     -srcfolder dmg-staging \
     -ov -format UDZO \
     "MLXManager-${{ github.ref_name }}.dmg"
   ```
   The symlink target is the absolute path `/Applications`. Inside the mounted DMG, Finder resolves this to the system Applications folder, enabling drag-and-drop installation.
6. **Publish release** — `softprops/action-gh-release@v2`:
   - Name: `${{ github.ref_name }}`
   - Body: see Release Notes Format below
   - Files: `MLXManager-${{ github.ref_name }}.dmg`
   - Uses default `GITHUB_TOKEN` — no additional secrets required

## Release Notes Format

```
MLXManager ${{ github.ref_name }}

See the [README](https://github.com/${{ github.repository }}/blob/main/README.md) for installation and usage.
```

`${{ github.repository }}` resolves to `owner/repo` automatically — no hardcoded owner.

## No Tests in Release Job

Tests are a developer-local responsibility enforced by the Red-Green TDD workflow in `AGENTS.md`. The release job does not run `swift test`. This is a deliberate tradeoff: release CI stays fast and simple; test correctness is the developer's gate before tagging.

## Out of Scope

- **`Info.plist` version injection**: `CFBundleShortVersionString` remains static (`1.0`). The `.app` version shown in Finder will not match the release tag. Acceptable for now — can be added later with a `PlistBuddy` step.
- **Notarization**: Ad-hoc signing only. Gatekeeper will prompt on first launch. Full notarization requires an Apple Developer account and is out of scope.

## Versioning Convention

Tags follow `vMAJOR.MINOR.PATCH` (e.g. `v1.0.0`). No enforced policy — the developer decides when to tag.

## Files Changed

| File | Action |
|------|--------|
| `.github/workflows/release.yml` | Create |

No changes to `Makefile`, `Sources/`, or `Tests/`.
