# nimfoot v0 - Chunk 4/8: Macros + Cap Counter (Track D)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. Verify output shows `main` (Chunk 1 must have run `git init` if not a repo)
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches

## Context

This is the **Macros + Cap Counter** chunk (Track D). Both tasks depend on **Chunk 1's A7** (intercept combinator). This chunk is independent of Chunks 2 (config) and 3 (async) and may run in parallel with them after Chunk 1 commits.

Tasks in this chunk:
- **D1** — `expect` / `assert` DSL macros + `sandbox:` / `test:` wiring (`src/nimfoot/macros.nim`). The user-facing DSL surface.
- **D2** — Compile-time cap counter (`src/nimfoot/cap_counter.nim`, **Defense 3**). Ensures every TRM call is counted at compile time so no external call escapes authorization.

Within-track sequence: **D1 → D2**.

Previous chunks completed: **Chunk 1 (Track A foundation)**.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Tasks D1 and D2 (macros + cap counter). Fully autonomous."
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

After EACH task (D1, then D2), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. D1 completes all 4 gates before D2 begins.

### Post-Chunk Gates (after D1 and D2 pass per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all tests must pass.
2. Commit chunk completion with message `macros: implement tasks D1-D2 (expect/assert DSL + cap counter Defense 3)`

## Pre-conditions

- Chunk 1 committed to `main`: Track A foundation done, including A7 `intercept.nim`
- `src/nimfoot/intercept.nim` exists and exports `nimfootInterceptBody`
- Working tree clean before starting D1
- `nimble test` passes on the Chunk 1 commit baseline

## Exit Criteria

- Tasks D1 and D2 complete with all 4 per-task gates passed
- `src/nimfoot/macros.nim` exists and exports `expect`, `assert`, `sandbox:`, `test:` DSL macros
- `src/nimfoot/cap_counter.nim` exists and implements Defense 3 (compile-time cap tracking)
- All chunk tests passing (`nimble test` clean)
- Chunk commit created on `main` with message `macros: implement tasks D1-D2 (expect/assert DSL + cap counter Defense 3)`
- Working tree clean

## Next

When complete, run the next chunk:
```
Follow the prompt in /Users/eek/Development/nimfoot/.claude/prompts/nimfoot-v0-chunk-5.md
```

Note: Chunks 2, 3, and 4 are mutually independent after Chunk 1. Chunk 5 requires Chunks 1 + 4 (A + D). Chunk 6 requires Chunks 1 + 3 + 4 (A + C + D). Chunks 5 and 6 are independent of each other once their deps are met.
