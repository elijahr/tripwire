# nimfoot v0 - Chunk 2/8: Config (Track B)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. Verify output shows `main` (Chunk 1 must have run `git init` if not a repo)
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches

## Context

This is the **Config** chunk (Track B, a single task). It depends only on **Chunk 1's A1** (`nimfoot.nimble` manifest with `parsetoml`) — it does NOT depend on A2+ types. This chunk is independent of Chunks 3 (async) and 4 (macros) and may be run in parallel with them after Chunk 1 commits.

Task in this chunk:
- **B1** — Config loader + discovery (`src/nimfoot/config.nim`). Defines `NimfootConfig`, including `allowPendingAsync*: bool`, `allow_pending_async` TOML key parsing, and config discovery (walk up from cwd to find `nimfoot.toml`). Uses `parsetoml`.

Previous chunks completed: **Chunk 1 (Track A foundation)**.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Task B1 (config loader). Fully autonomous."
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

After EACH task (B1), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. Since this chunk has a single task, all 4 gates run once on B1 before the chunk closes.

### Post-Chunk Gates (after B1 passes per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all tests must pass (prior chunks' tests + new B1 tests)
2. Commit chunk completion with message `config: implement task B1 (config loader + discovery)`

## Pre-conditions

- Chunk 1 committed to `main`: `nimfoot.nimble` exists and declares `parsetoml >= 0.7.0`
- `src/nimfoot/` directory exists from Track A
- Working tree clean before starting B1
- `nimble test` passes on the Chunk 1 commit baseline

## Exit Criteria

- Task B1 complete with all 4 per-task gates passed
- `src/nimfoot/config.nim` exists and exports `NimfootConfig` type and loader procs
- All chunk tests passing (`nimble test` clean)
- Chunk commit created on `main` with message `config: implement task B1 (config loader + discovery)`
- Working tree clean

## Next

When complete, run the next chunk:
```
Follow the prompt in /Users/eek/Development/nimfoot/.claude/prompts/nimfoot-v0-chunk-3.md
```

Note: Chunks 2, 3, and 4 are independent siblings of Chunk 1. If running sequentially, order is 2 → 3 → 4. If running in parallel, they can be dispatched concurrently.
