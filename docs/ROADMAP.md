# MLX Manager — Roadmap & Vision

> Living document capturing the direction, feature decisions, and open questions for MLX Manager.

---

## Current State (March 2026)

**What it is:** A native macOS menu bar application (Apple Silicon) for managing MLX LLM server instances.

**Core features:**
- One-click server start/stop/restart
- Live progress monitoring via log parsing
- Dual backend support (`mlx-lm` and `mlx-vlm`)
- Config presets for different models/context sizes
- RAM monitoring
- Auto-bootstrap of Python environment via `uv`
- Process recovery on app launch

**Tech stack:** Swift 5.9+, AppKit, XCTest, Swift Package Manager

---

## Immediate Priority: Architecture Refactor

**Status:** In progress (8 tasks defined in `docs/superpowers/plans/2026-03-24-architecture-refactor.md`)

**Tasks:**
1. ✅ Make `StatusBarController.presets` mutable
2. ✅ Replace nuclear rebuild with in-place updates
3. ✅ Eliminate duplicated "running" state
4. ⏳ Extract `ServerCoordinator`
5. ⏳ Wire `ServerCoordinator` into `AppDelegate`
6. ⏳ Cleanup/polish passes

**Why:** Addresses structural debt — nuclear rebuilds, duplicated state, silent errors, poorly bounded responsibilities.

---

## Feature Decisions

### ❌ Not Prioritized

**Chat Interface**
- *Reasoning:* Many alternatives exist; users won't use this for chat
- *Caveat:* Could be useful for debugging, but not a core feature

### ⚠️ Questionable / Needs Thought

**Multi-Server Support**
- *Complexity:* Each backend can already support multiple models ad-hoc
- *Reality:* Concurrent inference is unlikely to be desired
- *Use case:* May want separate servers for vision vs. text backends
- *Status:* Needs more investigation before implementation

**Model Download Manager**
- *Current state:* Download progress already appears in logs
- *With log display enabled:* Functionality is partially there
- *Assessment:* Nice-to-have but not critical
- *Status:* Low priority

---

## Long-Term Vision

### Minimalist Server Controller

> A polished control surface on top of the MLX server — nothing more, nothing less.

**Core philosophy:**
- Stay focused on server management
- Don't become a full AI dashboard
- Don't compete with dedicated chat clients
- Polish the existing feature set

**Desired feature set:**
1. Reliable server lifecycle management
2. Accurate progress/completion detection
3. Clean preset management (import/export)
4. Optional: Enhanced metrics (latency, throughput)
5. Optional: Better visual feedback (status notifications)

---

## Open Questions

### Technical

1. **Multi-server architecture:** If we do support multiple servers, should they be:
   - Separate app instances?
   - Multiple servers within one instance?
   - A hybrid approach?

2. **Completion detection:** Current approach uses `KV Caches:` and `POST 200` signals. Is there a more reliable signal we're missing?

3. **Settings migration:** No strategy exists yet for schema changes.

### Product

1. **Publishing:** Is this worth publishing as a standalone app?
   - Fills a real gap for local MLX users
   - Would require proper signing, distribution setup

2. **CLI mode:** Should functionality be exposed as a CLI tool with GUI as optional "watch mode"?

---

## Recommendations

### Phase 1: Foundation (Current)
- ✅ Complete architecture refactor
- ✅ Polish existing features
- ✅ Add import/export for presets

### Phase 2: Enhancement (Post-Refactor)
- ⏳ Enhanced metrics display (latency, tokens/second)
- ⏳ Status notifications
- ⏳ Better error handling (reduce silent `try?` swallows)

### Phase 3: Re-evaluate (After Phase 2)
- ⏳ Decide on multi-server support
- ⏳ Consider publishing
- ⏳ Consider CLI mode

---

## Notes

**User preferences (Stefano):**
- Values minimalism over feature bloat
- Prefers system-level solutions over model skills
- Wants maximum efficiency, no bullshit
- Direct communication style

**Methodology:**
- OpenSpec: All work is spec-driven
- Red-Green TDD: Failing test first, always

---

*Last updated: March 24, 2026*
