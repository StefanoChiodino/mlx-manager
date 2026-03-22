# AGENTS.md — MLX Manager

## Red-Green TDD — By the Book

Every unit of behaviour is driven by a failing test first.

**The cycle is strictly:**

1. **RED** — Write the smallest failing test that describes the behaviour. Run it. Confirm it fails for the right reason (not a compile error, not wrong assertion — the right reason).
2. **GREEN** — Write the minimum production code to make it pass. No more.
3. **REFACTOR** — Clean up without changing behaviour. Tests must stay green.

**Rules:**

- Never write production code before a failing test exists
- Never write more production code than needed to pass the current test
- Never skip the red step ("I know it'll fail") — run it and show the output
- Test file lives alongside source: `Sources/Foo.swift` → `Tests/FooTests.swift`
- Use XCTest (Swift native)
- Each test method tests exactly one behaviour

## Project Context

See `docs/PROJECT.md` for tech stack, architecture, and domain knowledge.
See `docs/SPEC.md` for the full requirements spec.
