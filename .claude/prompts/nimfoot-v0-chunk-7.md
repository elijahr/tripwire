# nimfoot v0 - Chunk 7/8: Auto + Facade (Track G)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. Verify output shows `main` (Chunk 1 must have run `git init` if not a repo)
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches

## Context

This is the **Auto + Facade** chunk (Track G). Tasks depend on **Chunk 6 (all plugins ready)**, **Chunk 5 (E1 integration_unittest)**, and **Chunk 2 (B1 config)** plus the full Track A foundation (Chunk 1).

Tasks in this chunk:
- **G1** — `auto.nim` umbrella module (`src/nimfoot/auto.nim`). This is the file that test binaries import via `--import:nimfoot/auto` (the global TRM injection mechanism). It re-exports every plugin so a single `--import:nimfoot/auto` activates all TRMs. Depends on F1, F4, F7 (all plugin modules must exist).
- **G2** — Facade (`src/nimfoot.nim`) — full re-exports + **Defense 1 guard**. The public API surface. Depends on G1, E1, and all of A, B. Defense 1 guards against re-import / duplicate-registration hazards.

Within-track sequence: **G1 → G2**.

Previous chunks completed: **Chunks 1, 2, 3, 4, 5, 6**.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Tasks G1 and G2 (auto.nim umbrella + nimfoot.nim facade with Defense 1). Fully autonomous."
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

After EACH task (G1, then G2), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. G1 completes all 4 gates before G2 begins.

### Post-Chunk Gates (after G1 and G2 pass per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all tests must pass.
2. Verify the facade compiles and exports the full public API surface.
3. Commit chunk completion with message `facade: implement tasks G1-G2 (auto.nim + nimfoot facade with Defense 1)`

## Pre-conditions

- Chunks 1 through 6 all committed to `main`
- `src/nimfoot/plugins/mock.nim`, `src/nimfoot/plugins/httpclient.nim`, `src/nimfoot/plugins/osproc.nim` all exist
- `src/nimfoot/integration_unittest.nim` (E1) exists
- `src/nimfoot/config.nim` (B1) exists
- Working tree clean before starting G1
- `nimble test` passes on the latest commit baseline

## Exit Criteria

- Tasks G1 and G2 complete with all 4 per-task gates passed
- `src/nimfoot/auto.nim` exists and re-exports all plugins
- `src/nimfoot.nim` facade exists and exports the full public API
- Defense 1 guard present in the facade (tested)
- All chunk tests passing (`nimble test` clean)
- Chunk commit created on `main` with message `facade: implement tasks G1-G2 (auto.nim + nimfoot facade with Defense 1)`
- Working tree clean

## Next

When complete, run the next chunk:
```
Follow the prompt in /Users/eek/Development/nimfoot/.claude/prompts/nimfoot-v0-chunk-8.md
```
