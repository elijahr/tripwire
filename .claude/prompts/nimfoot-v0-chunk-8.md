# nimfoot v0 - Chunk 8/8: Self-Tests + Docs (Track H, FINAL)

## Working Directory

**Path:** /Users/eek/Development/nimfoot
**Branch:** main (no worktree — work in current directory)

BEFORE ANY WORK:
1. `cd /Users/eek/Development/nimfoot && pwd && git branch --show-current`
2. Verify output shows `main` (Chunk 1 must have run `git init` if not a repo)
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/nimfoot`
4. Do NOT create new branches or switch branches

## Context

This is the **Self-Tests + Docs** chunk (Track H) and it is the **FINAL chunk** for nimfoot v0. It depends on **Chunk 7 (full system with facade in place)**.

Tasks in this chunk:
- **H1** — `all_tests.nim` aggregator + matrix validation. Depends on G2.
- **H2** — Self-test for the three guarantees (`tests/test_self_three_guarantees.nim`). Depends on H1. Exercises: (1) every external call pre-authorized, (2) every interaction asserted, (3) every mock consumed.
- **H3** — Defenses D3/D5/D6 regression suite. Depends on H1. Locks in cap-counter (D3), osproc fallback trap (D5), and any D6 invariant.
- **H4** — `docs/quickstart.md`. Depends on H1.
- **H5** — `docs/plugin-authoring.md` (13 Rules). Depends on H1.
- **H6** — Spike #2 cap REPORT.md (Appendix B deferred item). Depends on H1.
- **H6.5** — FFI audit module stub (`src/nimfoot/audit_ffi.nim`, Defense 2 Part 3). Depends on G2 (facade).
- **H7** — Full matrix CI smoke (final acceptance). Depends on H1, H2, H3, H4, H5, H6.5.

Within-track sequence: **H1 first**. H2, H3, H4, H5 then run in parallel after H1 (they are siblings with only an H1 dependency). H6 and H6.5 also depend only on H1/G2. H7 runs last and must wait on H1, H2, H3, H4, H5, H6.5. Sequentially, a safe order is: **H1 → H2 → H3 → H4 → H5 → H6 → H6.5 → H7**.

Previous chunks completed: **Chunks 1 through 7 (full nimfoot system: foundation, config, async, macros, test integration, plugins, facade)**.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-nimfoot/plans/2026-04-23-nimfoot-v0-impl.md, treat as ready. Tasks H1, H2, H3, H4, H5, H6, H6.5, H7 (self-tests, docs, FFI audit stub, final matrix). H7 is the final acceptance gate. Fully autonomous."
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

After EACH task (H1, H2, H3, H4, H5, H6, H6.5, H7), run these gates in order:

1. **TDD** (4.3): Dispatch subagent → must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent → must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent → must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. Each task completes all 4 gates before the next task begins.

**Docs-only tasks (H4, H5, H6):** the "TDD" gate for docs translates into a lint/example-build check — confirm code snippets inside the docs actually compile against the current facade. Do not skip the gate.

### Post-Chunk Gates (after all H tasks pass per-task gates)

1. Run `nimble test` from `/Users/eek/Development/nimfoot` — all tests must pass across the full matrix (or fewer cells per documented MVP cuts). Matrix axes: default, `-d:chronos`, `-d:nimfootUnittest2`, `--threads:on`, `--mm:orc`.
2. Commit chunk completion with message `self-tests+docs: implement tasks H1-H7 (final acceptance)` (include H6.5 in body).

## Pre-conditions

- Chunks 1 through 7 all committed to `main`
- `src/nimfoot.nim` facade exists (G2)
- `src/nimfoot/auto.nim` exists (G1)
- Working tree clean before starting H1
- `nimble test` passes on the Chunk 7 baseline

## Exit Criteria

- Tasks H1 through H7 (plus H6.5) complete with all 4 per-task gates passed
- `tests/all_tests.nim` aggregator exists and runs
- `tests/test_self_three_guarantees.nim` exists and passes
- D3/D5/D6 regression tests exist and pass
- `docs/quickstart.md`, `docs/plugin-authoring.md`, and Spike #2 cap `REPORT.md` exist with compilable examples
- `src/nimfoot/audit_ffi.nim` (H6.5 Defense 2 Part 3 stub) exists
- H7 full-matrix smoke passes (or documented MVP subset)
- Chunk commit created on `main` with message `self-tests+docs: implement tasks H1-H7 (final acceptance)`
- Working tree clean

## Final Steps

After all H tasks complete:

1. Run full test suite: `nimble test` — all 5 matrix cells (default, `-d:chronos`, `-d:nimfootUnittest2`, `--threads:on`, `--mm:orc`) must pass (or fewer per documented MVP cuts).
2. Comprehensive implementation audit (4.6.1) — confirm every plan task maps to a commit on `main`.
3. Green mirage audit (4.6.3) — must invoke `audit-green-mirage` skill using Skill tool.
4. Comprehensive fact-checking (4.6.4) — must invoke `fact-checking` skill using Skill tool over all self-tests and docs.
5. Pre-PR claim validation (4.6.5) — verify all README/docs claims against actual behavior.
6. Finishing — must invoke `finishing-a-development-branch` skill using Skill tool to present merge/PR/cleanup options to the user.
