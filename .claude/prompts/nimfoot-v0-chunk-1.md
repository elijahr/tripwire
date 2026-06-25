# nimfoot v0 - Chunk 1/8: Foundation (Track A)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. If `.git` does not exist, run `git init` to initialize the repo, then create the first commit `chore: initialize repo with docs and spike baseline` containing the existing `docs/` and `spike/` trees on branch `main` (rename from `master` if needed via `git branch -m master main`). Verify `git branch --show-current` then prints `main`.
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches (stay on `main`)

## Context

This is the **Foundation** chunk. It is the first chunk of the nimfoot v0 implementation and depends on no prior chunks. Greenfield start: only `docs/` and `spike/` exist under `/Users/eek/Development/nimfoot`.

This chunk lays down Track A end-to-end:
- **A1** — `nimfoot.nimble` package manifest (`parsetoml` required, `chronos` optional)
- **A2** — Base types (`src/nimfoot/types.nim`): `Plugin`, `Verifier`, `Interaction`, `Expectation`, etc.
- **A3** — Error hierarchy (`src/nimfoot/errors.nim`): `NimfootDefect` vs `NimfootError` two-root split, `PendingAsyncDefect`, `AssertionInsideSandboxError`, etc.
- **A3.5** — Context module (`src/nimfoot/context.nim`): `AssertionContext`, `assertionsOpen`, `inAssertBlock`, `inAnyOrder`
- **A3.6** — Plugin base methods (`src/nimfoot/plugin_base.nim`): `{.base.}` methods `assertableFields`, `formatInteraction`, `formatError`, `matches`. Modifies `errors.nim` message construction to call `formatInteraction`.
- **A4** — Registry (`src/nimfoot/registry.nim`): plugin registration
- **A5** — Timeline ops (`src/nimfoot/timeline.nim`): recording interactions
- **A6** — Sandbox + Verifier lifecycle (`src/nimfoot/sandbox.nim`, `src/nimfoot/verify.nim`): `sandbox:` template, `currentVerifier`, verifier stack
- **A7** — Intercept combinator (`src/nimfoot/intercept.nim`): the single `nimfootInterceptBody` used by every plugin TRM (cap-count, nil/active guard, mock pop, timeline record, spy-or-raise)

Within-track sequence: **A1 → A2 → A3 → A3.5 → A3.6 → A4 → A5 → A6 → A7**.

**File-serial constraints to honor:**
- A3 → A3.6 both modify `errors.nim` (run A3 first, then A3.6)
- A1 sets up `nimfoot.nimble`; all subsequent A-track tasks may touch it — coordinate sequentially
- A3.5 depends on A6 for test infrastructure, but per the plan A3.5 is placed after A3 in critical-path order; its tests use the `sandbox:` template from A6, so when running A3.5's TDD RED phase, you may need to stub or defer tests that depend on A6 until A6 lands. Follow the plan's guidance in each task section.

Previous chunks completed: **none (this is the first chunk)**.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Tasks A1, A2, A3, A3.5, A3.6, A4, A5, A6, A7 (Track A foundation). Fully autonomous."
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

After EACH task (A1, A2, A3, A3.5, A3.6, A4, A5, A6, A7), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. Each task completes all 4 gates before the next task begins.

### Post-Chunk Gates (after all tasks in this chunk pass per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all chunk tests must pass. Note: only tests written during this chunk will exist yet; verify the nimble test target resolves and passes.
2. Commit chunk completion with message `foundation: implement tasks A1-A7` (include A3.5 and A3.6 in commit body).

## Pre-conditions

- `/Users/eek/Development/nimfoot` exists and contains only `docs/` and `spike/` subdirectories (plus any `.claude/` prompts)
- `nim --version` reports 2.2.6 (via mise at `/Users/eek/.local/share/mise/installs/nim/2.2.6`)
- Git repo initialized on branch `main` (Chunk 1 Step 2 creates it if absent)
- Working tree clean before starting A1

## Exit Criteria

- All 9 Track A tasks (A1, A2, A3, A3.5, A3.6, A4, A5, A6, A7) complete with all 4 per-task gates passed
- All chunk tests passing (`nimble test` clean)
- Chunk commit created on `main` with message `foundation: implement tasks A1-A7`
- Working tree clean
- `src/nimfoot/` contains at minimum: `types.nim`, `errors.nim`, `context.nim`, `plugin_base.nim`, `registry.nim`, `timeline.nim`, `sandbox.nim`, `verify.nim`, `intercept.nim`
- `nimfoot.nimble` resolves `parsetoml` dependency

## Next

When complete, run the next chunk:
```
Follow the prompt in /Users/eek/Development/nimfoot/.claude/prompts/nimfoot-v0-chunk-2.md
```

Chunks 2, 3, and 4 each depend only on Chunk 1 and are mutually independent — they may be executed in parallel if the orchestrator supports it, or sequentially (2 → 3 → 4) in a single-thread setting.
