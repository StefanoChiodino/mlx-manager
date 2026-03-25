---
name: GitHub Releases via Git Tags
description: Automated GitHub Release pipeline triggered by git tags, producing a DMG with the MLXManager.app bundle
type: project
---

# GitHub Releases via Git Tags

## Overview

A single GitHub Actions workflow publishes a new GitHub Release whenever a version tag (e.g. `v1.0.0`) is pushed. The release asset is a `.dmg` containing the ad-hoc-signed `MLXManager.app` with a symlink to `/Applications` for drag-and-drop installation.

## Trigger

```
on:
  push:
    tags:
      - 'v*'
```

Push a tag → release. No manual dispatch. No branch conditions.

## Runner

`macos-15` — Apple Silicon GitHub-hosted runner. Required because `swift build` on this project targets Apple Silicon.

## Job: `release`

Single job, no artifact handoff between jobs.

### Steps

1. **Checkout** — `actions/checkout@v4`
2. **Build** — `swift build -c release`
   - Produces `.build/release/MLXManagerApp`
3. **Bundle** — Inline shell replicating `make bundle`:
   - `mkdir -p build/MLXManager.app/Contents/MacOS build/MLXManager.app/Contents/Resources`
   - Copy binary → `Contents/MacOS/MLXManager`
   - Copy `Resources/Info.plist` → `Contents/Info.plist`
   - `iconutil -c icns Resources/AppIcon.iconset -o Contents/Resources/AppIcon.icns`
   - Copy `Sources/MLXManagerApp/presets.yaml` → `Contents/Resources/presets.yaml`
   - Copy `Resources/LaunchAgent.plist` → `Contents/Resources/LaunchAgent.plist`
4. **Sign** — `codesign --force --deep -s - build/MLXManager.app` (ad-hoc)
5. **Create DMG** — `hdiutil create` with:
   - Source: temp staging directory containing `MLXManager.app` and a `/Applications` symlink
   - Output: `MLXManager-${{ github.ref_name }}.dmg`
   - Format: `UDZO` (compressed)
6. **Publish release** — `softprops/action-gh-release@v2`:
   - Name: `${{ github.ref_name }}`
   - Body: tag name + link to README on `main`
   - Files: `MLXManager-${{ github.ref_name }}.dmg`
   - Uses default `GITHUB_TOKEN` — no additional secrets required

## Release Notes Format

```
MLXManager ${{ github.ref_name }}

See the [README](https://github.com/<owner>/mlx-manager/blob/main/README.md) for installation and usage.
```

## No Tests in Release Job

Tests are a developer-local responsibility (per project TDD workflow). The release job does not run `swift test` — this avoids CI flakiness from environment differences and keeps the release pipeline fast.

## Versioning Convention

Tags follow `vMAJOR.MINOR.PATCH` (e.g. `v1.0.0`). No enforced policy — the developer decides when to tag.

## Files Changed

| File | Action |
|------|--------|
| `.github/workflows/release.yml` | Create |

No changes to `Makefile`, `Sources/`, or `Tests/`.
