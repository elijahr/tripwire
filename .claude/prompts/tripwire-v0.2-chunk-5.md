# Tripwire v0.2 — Chunk 5/5: Ergonomic overlay + typestate spike + docs + aggregation (WI5)

## Working Directory

**Path:** `/Users/eek/Development/tripwire`
**Branch:** `main`

BEFORE ANY WORK:
1. `cd /Users/eek/Development/tripwire && pwd && git branch --show-current`
2. Verify output shows `main`
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/tripwire`
4. Do NOT create new branches or switch branches (trunk-based; session preference `worktree: none`)

## Context

This chunk lands Work Item 5 of Tripwire v0.2: the final surface polish and release artifacts. It aggregates `tests/all_tests.nim` imports for all new threads + async_registry tests (sole owner per File-serial constraints), adds the `sandbox(name, body)` overload (M4), runs the optional typestate probe under a 30-minute budget with a CUT-CLEAN gate (M5 — either ships under `-d:tripwireInternalTypestate` off-by-default with all four §7.2 gates green, OR is absent with findings rolled into the v0.3 roadmap), authors the CHANGELOG v0.2 entry with migration recipe (M6), updates README's alpha banner + v0.2 capabilities callout (M6), creates `docs/roadmap-v0.3.md` enumerating all §11 non-goals (M7), and bumps `tripwire.nimble` to `0.2.0`.

Previous chunks completed: Chunks 1, 2, 3, AND 4 — all WI1-WI4 work landed on `main`. Chunks 3 and 4 may have merged in either order. This chunk requires BOTH.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md, treat as ready. Tasks 5.0.5, 5.1, 5.2, 5.3, 5.4 (conditional), 5.5, 5.6, 5.7 (Work Item 5). Fully autonomous."
```

**Key documents:**
- Implementation plan: `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md`
- Design document: `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-design.md`
- Understanding document: `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/understanding/understanding-tripwire-v0.2-2026-04-23.md`

## Subagent Dispatch Discipline

<CRITICAL>
The develop skill orchestrates via subagents. Every subagent that does
substantive work MUST invoke the appropriate skill using the Skill tool.

"Do TDD" is NOT the same as "invoke the test-driven-development skill."
"Review the code" is NOT the same as "invoke the requesting-code-review skill."
Doing the work without invoking the skill is a workflow violation.
Skills contain specialized logic that ad-hoc execution cannot replicate.

Every subagent prompt MUST begin with:
  "First, invoke the [skill-name] skill using the Skill tool.
   Then follow its complete workflow."

After each subagent returns, verify its output contains
"Launching skill: [name]". If not found, re-dispatch with explicit
instruction to invoke the skill.
</CRITICAL>

### Per-Task Gate Sequence (mandatory, sequential, not batched)

After EACH task, run these gates in order:

1. **TDD** (4.3): Dispatch subagent -> must invoke `test-driven-development` skill using the Skill tool
2. **Completion verification** (4.4): Dispatch subagent with inline audit prompt (no skill invocation needed)
3. **Code review** (4.5): Dispatch subagent -> must invoke `requesting-code-review` skill using the Skill tool
4. **Fact-checking** (4.5.1): Dispatch subagent -> must invoke `fact-checking` skill using the Skill tool

Do NOT batch gates across tasks. Each task completes all 4 gates before
the next task begins.

**Task-specific notes per the impl plan:**
- Task 5.0.5 MUST run FIRST in this chunk — sole owner of `tests/all_tests.nim`; adds imports for ALL new `tests/threads/*.nim` (8 files) and `tests/async_registry/*.nim` (6 files). Integration-only TDD (run `nimble test` before and after).
- Task 5.1 (named sandbox overload): full RED→GREEN; bind list matches existing `sandbox` at `sandbox.nim:50` verbatim (`popVerifier, pushVerifier, newVerifier, getCurrentException`).
- Task 5.2 (CHANGELOG): doc task; quality gate is reviewer walk-through of migration recipe.
- Task 5.3 (typestate probe): OPTIONAL; 30-minute budget; CUT-CLEAN if any of §7.2's four gates (a-d) fails. Do NOT push past 30 min.
  - Gate (a): `nim c src/tripwire.nim` compiles with identical signatures
  - Gate (b): `nimble test` passes with AND without `-d:tripwireInternalTypestate` under both `--gc:refc` and `--gc:orc`
  - Gate (c): plugin TRM codegen size diff < 5% (measure via `size -d` on stripped binary; OQ3 says resolve the `strip -S` vs `strip --strip-all` choice at task start)
  - Gate (d): `=copy` / `=sink` behavior unaffected in multi-verifier nested-sandbox test
- Task 5.4 (typestate expansion): CONDITIONAL on 5.3 passing ALL gates. If 5.3 cut-clean, SKIP 5.4 entirely; roadmap captures findings via 5.6.
- Task 5.5 (README): doc task; ≤15-line capabilities callout linking to CHANGELOG; reviewer read-through gate.
- Task 5.6 (roadmap-v0.3.md): RED against `tests/test_docs_presence.nim` adding an assertion for the new file, then GREEN by creating it.
- Task 5.7 (version bump + matrix report): integration-only; bumps `tripwire.nimble` version to `0.2.0`. Creates matrix report at `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/notes/wi5-final-matrix-report.md`. Release tag is NOT created (user's call per OQ4).

### Post-All-Tasks Gates (mandatory, end of this chunk)

After all tasks in this chunk pass per-task gates:

1. Comprehensive implementation audit (4.6.1) — inline audit prompt covering WI1-WI5 end-to-end (entire v0.2 surface)
2. Full test suite (4.6.2) — dispatch subagent to run `nimble test` across all 7 matrix cells (or 8 if typestate ships under a new conditional cell per §9; 7 if typestate cut-clean); verify negative refc+threads build test still fires `{.error.}`; verify M1-M7 + M1b + M2b + M3b + M-matrix all green
3. Green mirage audit (4.6.3) -> must invoke `auditing-green-mirage` skill using the Skill tool
4. Comprehensive fact-checking (4.6.4) -> must invoke `fact-checking` skill using the Skill tool
5. Finishing (4.7) -> must invoke `finishing-a-development-branch` skill using the Skill tool

## Pre-conditions

- Chunks 1, 2, 3, AND 4 all committed to `main`. Verify:
  - `git log --oneline` shows WI1 through WI4 commits
  - `git grep 'futureRegistry' src/tripwire/sandbox.nim` returns the field declaration
  - `src/tripwire/threads.nim` exists (WI3)
  - `src/tripwire/async_registry.nim` exists (WI4)
  - `src/tripwire/async_registry_types.nim` exists (WI2)
  - `src/tripwire/verify.nim` contains `drainPendingAsync` (WI4)
  - `src/tripwire/errors.nim` contains `ChronosOnWorkerThreadDefect`, `NestedTripwireThreadDefect`, and the overloaded `newPendingAsyncDefect(msg, parent)` (WI2)
  - All `tests/threads/*.nim` files (from WI3) and `tests/async_registry/*.nim` files (from WI4) exist
  - `tripwire.nimble` matrix has cell #7 (orc+threads) added by WI3 Task 3.9
- `git status` clean on `main`
- `nimble test` passes 7 cells (cells 1-6 from v0.1, cell #7 from WI3). If `tests/threads/*.nim` and `tests/async_registry/*.nim` are not yet aggregated into `tests/all_tests.nim`, the standalone runs of each test file must pass — Task 5.0.5's job is precisely to aggregate them.
- `nim --version` reports 2.2.x

## Exit Criteria

- All required Tasks (5.0.5, 5.1, 5.2, 5.5, 5.6, 5.7) committed on `main`. Optional tasks: 5.3 (probe) committed only if gates pass; 5.4 (expansion) committed only if 5.3 passes.
- All per-task gates passed (TDD for RED-target tasks, completion verify, code review, fact-check)
- `tests/all_tests.nim` imports ALL new `tests/threads/*.nim` tests (8 files: `test_tripwire_thread_basic.nim`, `test_tripwire_thread_multi.nim`, `test_tripwire_thread_exception.nim`, `test_tripwire_thread_nested_sandbox.nim`, `test_tripwire_thread_reject_chronos.nim`, `test_tripwire_thread_reject_nested.nim`, `test_tripwire_thread_nested_sandbox_spawn.nim`, `test_refc_threads_rejected.nim`) AND ALL new `tests/async_registry/*.nim` tests (6 files: `test_async_check_leak_repro.nim`, `test_async_check_generation_repro.nim`, `test_async_check_basic.nim`, `test_async_check_drain_timeout.nim`, `test_plain_async_check_still_raises.nim`, `test_chronos_future_rejected.nim`)
- `src/tripwire/sandbox.nim` has `template sandbox*(name: string, body: untyped)` overload landing alongside the existing `sandbox*(body: untyped)`; bind list matches verbatim; named form sets `v.name = name`; both forms compile without ambiguity; all pre-existing tests pass
- `CHANGELOG.md` has `## v0.2.0 — UNRELEASED` section with Breaking, Added, Changed, and Deferred-to-v0.3 subsections, including env-var removal AND orc/arc requirement AND a copy-pasteable migration recipe (per design §10.2 lines 1397-1464)
- Typestate probe (Task 5.3) outcome documented one of two ways:
  - **PASSED all four gates**: `when defined(tripwireInternalTypestate):` block lands in `sandbox.nim` (default build unchanged); `tripwire.nimble` adds `requires "typestates >= 0.3.1"` conditionally; Task 5.4 extends the block to the full `Idle → Recording → Asserting → Verified` lifecycle per §7.3; `tests/typestate/test_typestate_lifecycle.nim` runs GREEN under the define
  - **CUT CLEAN**: no code changes to `sandbox.nim` or `tripwire.nimble`; findings recorded in `docs/roadmap-v0.3.md` Section 11
- `README.md` alpha banner mentions orc/arc requirement AND env-var removal; adds ≤15-line v0.2 capabilities callout (tripwireThread, asyncCheckInSandbox, FFI auto-discovery, named sandbox overload) linking to CHANGELOG.md for migration
- `docs/roadmap-v0.3.md` exists and enumerates all §11 non-goals plus the §8 refc+threads roadmap entry; 11 sections (plus a conditional Section 11 if typestate cut-clean). `tests/test_docs_presence.nim` has a new assertion for this file and still passes other asserts
- `tripwire.nimble` version bumped from `0.0.1` to `0.2.0`
- `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/notes/wi5-final-matrix-report.md` exists capturing the green matrix run
- Full matrix `nimble test` passes across all cells:
  - 6 pre-existing cells (1-6)
  - Cell #7 orc+threads (M-matrix)
  - If typestate probe passed: a new typestate-enabled cell per §9 (budget: `--gc:orc --define:tripwireActive --define:tripwireInternalTypestate --import:tripwire/auto`) runs green
  - Negative refc+threads build test still fires `{.error.}` with expected message
- v0.2 success metrics M1-M7 + M1b + M2b + M3b + M-matrix all verified green in the matrix report
- All changes committed to `main` with descriptive commit messages citing design sections
- Metrics achieved: M4 (reviewer confirms `withX` param-less + `name: body` labeled forms), M5 (typestate spike outcome — either shipped behind flag OR cut clean with roadmap entry), M6 (CHANGELOG + README + design aligned), M7 (`docs/roadmap-v0.3.md` exists with all sections)
- Quality gates passed (comprehensive audit, full test suite across ALL matrix cells, green mirage, fact-check)

## Next

This is the final chunk. After all exit criteria are met:

1. Run the full test suite across ALL matrix cells (`nimble test`). Confirm all 7 (or 8, if typestate shipped) cells green. Verify negative refc+threads build still fires its `{.error.}`.
2. Verify v0.2 success metrics M1-M7 (plus M1b, M2b, M3b, M-matrix) are green and documented in the matrix report at `/Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/notes/wi5-final-matrix-report.md`.
3. Dispatch a subagent to invoke the `finishing-a-development-branch` skill using the Skill tool. Pass:
   - feature name: `Tripwire v0.2`
   - branch: `main`
   - post_impl preference: `offer_options`

The subagent prompt MUST begin with: "First, invoke the `finishing-a-development-branch` skill using the Skill tool. Then follow its complete workflow." After the subagent returns, verify its output contains "Launching skill: finishing-a-development-branch"; if not found, re-dispatch with explicit instruction to invoke the skill.
