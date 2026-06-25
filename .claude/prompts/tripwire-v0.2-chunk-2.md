# Tripwire v0.2 — Chunk 2/5: Shared Verifier field + error types (WI2)

## Working Directory

**Path:** `/Users/eek/Development/tripwire`
**Branch:** `main`

BEFORE ANY WORK:
1. `cd /Users/eek/Development/tripwire && pwd && git branch --show-current`
2. Verify output shows `main`
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/tripwire`
4. Do NOT create new branches or switch branches (trunk-based; session preference `worktree: none`)

## Context

This chunk lands Work Item 2 of Tripwire v0.2: the shared plumbing that unblocks WI3 (threads) and WI4 (async registry). It introduces `src/tripwire/async_registry_types.nim` (the split-out `RegisteredFuture` type that breaks the circular import per Design Ratification DR1), adds `futureRegistry*: seq[RegisteredFuture]` to `Verifier`, declares two new defect types (`ChronosOnWorkerThreadDefect`, `NestedTripwireThreadDefect`), and adds the `newPendingAsyncDefect(msg, parent)` overload. No behavior change to v0.1 runtime: the 601 baseline must remain green after each commit.

Previous chunks completed: Chunk 1 (WI1 — FFI audit auto-discovery).

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md, treat as ready. Tasks 2.1-2.4 (Work Item 2). Fully autonomous."
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

**Task-specific TDD adjustments per the impl plan:**
- Task 2.1 (type-only file): TDD phases skipped; still run code review.
- Task 2.2 (field addition): no new RED test; capture `nimble test_fast` baseline, apply change, re-run to confirm GREEN.
- Task 2.3 (defect types + overload): full RED→GREEN cycle in `tests/test_errors.nim`.
- Task 2.4 (facade re-export check): integration-only; run `nimble test`.

### Post-All-Tasks Gates (mandatory, end of this chunk)

After all tasks in this chunk pass per-task gates:

1. Comprehensive implementation audit (4.6.1) — inline audit prompt
2. Full test suite (4.6.2) — dispatch subagent to run `nimble test` across matrix cells 1-6 (601 baseline) plus `tests/test_errors.nim`, `tests/test_sandbox.nim`, `tests/test_verifier.nim` to confirm no regression from the field addition
3. Green mirage audit (4.6.3) -> must invoke `auditing-green-mirage` skill using the Skill tool
4. Comprehensive fact-checking (4.6.4) -> must invoke `fact-checking` skill using the Skill tool

## Pre-conditions

- Chunk 1 committed to `main` (`git log --oneline` shows WI1 commits including `docs(wi1): baseline v0.1 audit_ffi env-var contract before removal` through `test(audit_ffi): update v0.1 tests for env-var removal`)
- `git status` clean on `main`
- `nimble test` passes all 6 pre-existing matrix cells
- `git grep 'TRIPWIRE_FFI_' src/ tests/` returns empty (confirms WI1 is fully landed)
- `nim --version` reports 2.2.x
- `src/tripwire/sandbox.nim:5-13` currently has the Verifier type (pre-future-registry); verify via grep before starting Task 2.2
- `src/tripwire/errors.nim` currently has `newPendingAsyncDefect(testName)` one-argument form at lines 135-139 (verify) and `newLeakedInteractionDefect` at lines 120-124 (verify)

## Exit Criteria

- All Tasks 2.1 through 2.4 acceptance criteria met, each landed as its own commit on `main`
- All per-task gates passed (TDD for applicable tasks, completion verify, code review, fact-check)
- `src/tripwire/async_registry_types.nim` exists, compiles standalone, and contains only the `RegisteredFuture` object type + `std/asyncfutures` import (per DR1)
- `Verifier.futureRegistry` field exists, defaults to `@[]` via Nim default-init, and is reachable from `src/tripwire/sandbox.nim`
- `sandbox.nim` imports `./async_registry_types` (NOT `./async_registry`); `git grep 'import .*async_registry\b' src/tripwire/sandbox.nim` returns only the `async_registry_types` line
- `errors.nim` declares `ChronosOnWorkerThreadDefect`, `NestedTripwireThreadDefect` (both subclasses of `TripwireDefect`), plus constructor procs `newChronosOnWorkerThreadDefect` and `newNestedTripwireThreadDefect` with the `site: tuple[filename: string, line: int, column: int]` signature
- `errors.nim` adds the `newPendingAsyncDefect*(msg: string, parent: ref Exception = nil): ref PendingAsyncDefect` overload; existing `newPendingAsyncDefect(testName)` signature AND message format remain unchanged
- `tests/test_errors.nim` exercises both new defect constructors, the overloaded `newPendingAsyncDefect`, AND the unchanged one-argument form (regression guard)
- `tripwire.nim` facade re-exports the new types via the existing `export errors` (verified by a toy `import tripwire; discard ChronosOnWorkerThreadDefect` compile in `tests/test_errors.nim`)
- `nimble test` passes all 6 pre-existing matrix cells (no behavioral change to v0.1 runtime)
- `tests/test_defenses.nim` and `tests/test_docs_presence.nim` still pass
- All changes committed to `main` with descriptive commit messages citing design sections
- Metrics: plumbing only (supports M1 and M2 downstream); no end-user metric is directly closed by this chunk
- Quality gates passed (comprehensive audit, full test suite, green mirage, fact-check)

## Next

Chunks 3 and 4 operate on disjoint files per the impl plan's File-serial constraints (Chunk 3 creates `threads.nim`; Chunk 4 creates `async_registry.nim` and modifies `integration_unittest.nim:85-86`; neither touches the other's surface, and `tests/all_tests.nim` aggregation is deferred to Chunk 5's Task 5.0.5). You MAY run Chunks 3 and 4 in parallel Claude Code sessions OR sequentially. The impl plan guarantees no file conflicts after the Finding #2 fix (Task 5.0.5 is the sole owner of `tests/all_tests.nim`).

**Sequential (recommended under `worktree: none`):**
```
Follow the prompt in .claude/prompts/tripwire-v0.2-chunk-3.md
```
then
```
Follow the prompt in .claude/prompts/tripwire-v0.2-chunk-4.md
```

**Parallel (advanced, separate sessions):** Start both `.claude/prompts/tripwire-v0.2-chunk-3.md` and `.claude/prompts/tripwire-v0.2-chunk-4.md` independently; re-run `nimble test` after each merges to `main`.
