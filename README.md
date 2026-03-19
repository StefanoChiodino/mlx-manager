# MLX Manager

A native macOS menu bar application (Apple Silicon) for managing MLX LLM server instances.

## Development Methodology

This project follows two non-negotiable disciplines — see [AGENTS.md](AGENTS.md) for the full rules:

- **OpenSpec** — all work is spec-driven. Read `openspec/` before touching code.
- **Red-Green TDD** — failing test first, always. No exceptions.

## Spec Structure

```text
openspec/
├── project.md              # Tech stack, architecture, domain knowledge
├── specs/
│   └── core/spec.md        # Source-of-truth requirements (Gherkin scenarios)
└── changes/                # Active proposals/designs/tasks (work in progress)
```

## Quick Reference

**Problem**: MLX server has no "100% complete" signal. Manual start/stop is tedious.

**Solution**: Menu bar app with one-click controls + log parsing for live progress.

**Stack**: Swift, AppKit (NSStatusItem), XCTest, Swift Package Manager.

## Working on This Repo

1. Read `AGENTS.md` first
2. Read `openspec/project.md` for domain context
3. Read `openspec/specs/core/spec.md` for current requirements
4. Check `openspec/changes/` for any active work in progress
5. Follow OpenSpec + Red-Green TDD — by the book
