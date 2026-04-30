# Task Guidelines

Tasks should be small enough for an agent to complete, verify, and explain in one pass.

## Task Shape

Each non-trivial task should state:

- Goal: user-visible result or engineering outcome.
- Scope: modules, files, or adapters that may change.
- Non-goals: explicit boundaries.
- Verification: commands or manual checks required before completion.

## Agent Workflow

1. Read `AGENTS.md` and the relevant `docs/` files.
2. Inspect existing code before proposing changes.
3. Keep edits scoped to the task and current module boundaries.
4. Prefer tests or mechanical checks for new behavior.
5. Update durable docs when behavior, commands, or architecture boundaries change.
6. Do not put temporary plans, investigation notes, or chat conclusions in `AGENTS.md`.

## Completion Report

Final reports should include:

- Changed files.
- Verification commands and results.
- Known gaps or skipped checks.
- Any follow-up that is required, not speculative.

## Escalation

If the task reveals architecture drift, update `docs/architecture.md` or `docs/quality.md`. If a new recurring workflow appears, document it here or in a focused docs file before relying on memory.
