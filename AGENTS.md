# AGENTS.md — MLX Manager

<openspec-instructions>

## Non-Negotiable Workflow Rules

This project follows two methodologies **by the book**. These are not suggestions.

### 1. OpenSpec — Spec-Driven Development

All work flows through the OpenSpec structure in `openspec/`. No feature, fix, or change is implemented without a corresponding spec artefact.

**The workflow is always:**

1. `/opsx:propose` — Write a proposal (`openspec/changes/<id>/proposal.md`)
2. `/opsx:apply` — Write design + tasks, then implement against them
3. `/opsx:archive` — Merge spec deltas into `openspec/specs/` and close the change

**Rules:**
- Read `openspec/specs/` before touching any code — it is the source of truth
- Read the active change's `proposal.md`, `design.md`, and `tasks.md` before writing code
- Update `tasks.md` as you complete each task (check off `[ ]` → `[x]`)
- Never implement anything not described in the current spec or active change
- Never skip the proposal step, even for small changes

### 2. Red-Green TDD — By the Book

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

### Combined Discipline

OpenSpec defines **what** to build. TDD defines **how** to build it. The tasks in `tasks.md` map 1:1 to test cases. Write the task → write the failing test → write the code.

</openspec-instructions>

## Project Context

See `openspec/project.md` for tech stack, architecture, and domain knowledge.
