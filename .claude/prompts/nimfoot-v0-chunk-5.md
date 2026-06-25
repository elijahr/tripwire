# nimfoot v0 - Chunk 5/8: Test Framework Integration (Track E)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. Verify output shows `main` (Chunk 1 must have run `git init` if not a repo)
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches

## Context

This is the **Test Framework Integration** chunk (Track E). Tasks depend on **Chunk 1 (A6 sandbox, A7 intercept)**, **Chunk 3 (C1 futures)**, and **Chunk 4 (D1 macros)**. E2 additionally depends on E1.

Tasks in this chunk:
- **E1** — `integration_unittest.nim` with `std/unittest` backend. Wires nimfoot's `test:` macro into the default Nim unittest runner. Imports: sandbox (A6), intercept (A7, for `PendingAsyncDefect`), futures (C1), macros (D1). Registers the exit-hook that calls `verifyAllOnExit` and raises `PendingAsyncDefect` on pending futures at shutdown.
- **E2** — `unittest2` backend compile check. Validates that the integration also compiles under the optional `unittest2` backend gated by `-d:nimfootUnittest2`.

Within-track sequence: **E1 → E2**.

Previous chunks completed: **Chunk 1 (Track A), Chunk 3 (Track C), Chunk 4 (Track D)**. Chunk 2 (config) is NOT a prerequisite for Chunk 5 but may have been done. Chunk 6 (plugins) is NOT a prerequisite but is a parallel sibling of Chunk 5.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Tasks E1 and E2 (unittest integration). Fully autonomous."
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

After EACH task (E1, then E2), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. E1 completes all 4 gates before E2 begins.

### Post-Chunk Gates (after E1 and E2 pass per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all tests must pass under the default `std/unittest` backend. Also verify the `-d:nimfootUnittest2` matrix cell compiles (E2 compile check).
2. Commit chunk completion with message `test-integration: implement tasks E1-E2 (unittest + unittest2 backends)`

## Pre-conditions

- Chunk 1 committed to `main`: `sandbox.nim` (A6), `intercept.nim` (A7), and `PendingAsyncDefect` type in `errors.nim` all exist
- Chunk 3 committed to `main`: `futures.nim` (C1) exists and exports asyncdispatch Future helpers
- Chunk 4 committed to `main`: `macros.nim` (D1) exists and exports the `test:` macro
- Working tree clean before starting E1
- `nimble test` passes on the latest commit baseline

## Exit Criteria

- Tasks E1 and E2 complete with all 4 per-task gates passed
- `src/nimfoot/integration_unittest.nim` exists and wires `std/unittest`
- `unittest2` backend compile-gate passes under `-d:nimfootUnittest2`
- All chunk tests passing (`nimble test` clean)
- Chunk commit created on `main` with message `test-integration: implement tasks E1-E2 (unittest + unittest2 backends)`
- Working tree clean

## Next

When complete, run the next chunk:
```
Follow the prompt in /Users/eek/Development/nimfoot/.claude/prompts/nimfoot-v0-chunk-6.md
```

Note: Chunks 5 and 6 are independent of each other. If the orchestrator runs them sequentially, 5 → 6 is fine. If parallel-capable, both can be dispatched concurrently once their deps are met.
