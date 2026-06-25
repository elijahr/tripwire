# nimfoot v0 - Chunk 3/8: Async Helpers (Track C)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. Verify output shows `main` (Chunk 1 must have run `git init` if not a repo)
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches

## Context

This is the **Async Helpers** chunk (Track C). It depends only on **Chunk 1's A1** (nimble manifest) for C1 and internally C2 depends on C1. It is independent of Chunks 2 (config) and 4 (macros) and may run in parallel with them after Chunk 1 commits.

Tasks in this chunk:
- **C1** — `asyncdispatch` Future helpers (`src/nimfoot/futures.nim`). Detection of pending futures, used to back Defense 3 (PendingAsyncDefect) wiring that lands later in Track E.
- **C2** — `chronos` overlay test. Validates behavior under optional `-d:chronos` build flag. Gated by the `chronos >= 4.2.2` optional dependency.

Within-track sequence: **C1 → C2**.

Previous chunks completed: **Chunk 1 (Track A foundation)**.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Tasks C1 and C2 (async helpers). Fully autonomous."
```

**Key documents:**
- Implementation plan: /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md
- Design document: /Users/eek/Development/nimfoot/docs/design/v0.md
- Mirror design doc: /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-design.md

## Subagent Dispatch Discipline

<CRITICAL>
The develop skill orchestrates via subagents. Every subagent that does substantive work MUST invoke the appropriate skill using the Skill tool.

"Do TDD" is NOT the same as "invoke the test-driven-development skill."
"Review the code" is NOT the same as "invoke the requesting-code-review skill."
Doing the work without invoking the skill is a workflow violation.

Every subagent prompt MUST begin with:
  "First, invoke the [skill-name] skill using the Skill tool. Then follow its complete workflow."

After each subagent returns, verify its output contains "Launching skill: [name]". If not found, re-dispatch with explicit instruction to invoke the skill.
</CRITICAL>

### Per-Task Gate Sequence (mandatory, sequential, not batched)

After EACH task (C1, then C2), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. C1 completes all 4 gates before C2 begins.

### Post-Chunk Gates (after C1 and C2 pass per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all tests must pass. Also verify that the chronos overlay test in C2 builds and passes when compiled with `-d:chronos` (if chronos is installed locally).
2. Commit chunk completion with message `async: implement tasks C1-C2 (future helpers + chronos overlay)`

## Pre-conditions

- Chunk 1 committed to `main`: `nimfoot.nimble` exists; `chronos` listed as optional dep
- `src/nimfoot/` directory exists from Track A
- Working tree clean before starting C1
- `nimble test` passes on the Chunk 1 commit baseline

## Exit Criteria

- Tasks C1 and C2 complete with all 4 per-task gates passed
- `src/nimfoot/futures.nim` exists and exports asyncdispatch Future detection helpers
- Chronos overlay test compiles/passes under `-d:chronos` (or is cleanly skipped when chronos is unavailable)
- All chunk tests passing (`nimble test` clean, both default and `-d:chronos` matrix cells if applicable)
- Chunk commit created on `main` with message `async: implement tasks C1-C2 (future helpers + chronos overlay)`
- Working tree clean

## Next

When complete, run the next chunk:
```
Follow the prompt in /Users/eek/Development/nimfoot/.claude/prompts/nimfoot-v0-chunk-4.md
```

Note: Chunks 2, 3, and 4 are independent siblings of Chunk 1. If running sequentially, order is 2 → 3 → 4. If running in parallel, they can be dispatched concurrently.
