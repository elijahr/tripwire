# Tripwire v0.2 — Chunk 3/5: tripwireThread family (WI3)

## Working Directory

**Path:** `/Users/eek/Development/tripwire`
**Branch:** `main`

BEFORE ANY WORK:
1. `cd /Users/eek/Development/tripwire && pwd && git branch --show-current`
2. Verify output shows `main`
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/tripwire`
4. Do NOT create new branches or switch branches (trunk-based; session preference `worktree: none`)

## Context

This chunk lands Work Item 3 of Tripwire v0.2: the `tripwireThread` family that lets user-spawned worker threads inherit the parent's Verifier so a TRM fired on a child thread lands on the parent timeline. It creates `src/tripwire/threads.nim` with `tripwireThread[T]`, `runWithVerifier`, `withTripwireThread`, `childEntry`, and the `ThreadHandoff` type; adds matrix cell #7 (orc+threads) to `tripwire.nimble`; and emits a compile-time `{.error.}` for `--gc:refc --threads:on` (F2) and for `--threads:off` (F1). Happy path, multi-child, exception propagation, nested-sandbox, chronos-rejection, and nested-tripwireThread rejection tests all land in `tests/threads/*.nim`.

Previous chunks completed: Chunk 1 (WI1 — FFI audit auto-discovery) and Chunk 2 (WI2 — Shared Verifier field + error types). Chunk 4 (WI4) may also be in flight or already landed, depending on whether sessions ran in parallel.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md, treat as ready. Tasks 3.1-3.9 (Work Item 3). Fully autonomous."
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
- Task 3.1 (GC-safety probe report): documentation-only; code-review only.
- Task 3.2 (implement `threads.nim`): stub-first RED, then fill in per design §3.2.
- Tasks 3.3-3.8 are RED→GREEN test cycles against the real implementation.
- Task 3.9 adds the matrix cell wire-up and the negative refc+threads build test; `tests/all_tests.nim` is NOT modified here (deferred to Chunk 5 Task 5.0.5).

### Post-All-Tasks Gates (mandatory, end of this chunk)

After all tasks in this chunk pass per-task gates:

1. Comprehensive implementation audit (4.6.1) — inline audit prompt
2. Full test suite (4.6.2) — dispatch subagent to run `nimble test` covering cells 1-6 AND the new cell #7 (orc+threads); validate each new `tests/threads/*.nim` module runs green individually (cell #7 aggregate verification lands in Chunk 5 Task 5.0.5, but every module must pass standalone here); run the negative refc+threads build and confirm its `{.error.}` fires with the expected message
3. Green mirage audit (4.6.3) -> must invoke `auditing-green-mirage` skill using the Skill tool
4. Comprehensive fact-checking (4.6.4) -> must invoke `fact-checking` skill using the Skill tool

## Pre-conditions

- Chunk 2 committed to `main` (required). Verify:
  - `git log --oneline` shows WI2 commits including `feat(async): RegisteredFuture type shared between sandbox and async_registry`, `feat(sandbox): add futureRegistry field to Verifier (design §4.3)`, `feat(errors): add thread-rejection defects + overloaded newPendingAsyncDefect (design §2.3, §3.6)`, `chore(wi2): confirm facade re-exports new types; pre-WI3/WI4 gate`
  - `git grep 'futureRegistry' src/tripwire/sandbox.nim` returns the field declaration
  - `git grep 'ChronosOnWorkerThreadDefect\|NestedTripwireThreadDefect' src/tripwire/errors.nim` returns both type declarations and both constructor signatures
- `git status` clean on `main`
- `nimble test` passes (6 cells if Chunk 4 hasn't merged yet; 6 or 7 cells depending on parallel-session state)
- GC-safety probe source exists at `/Users/eek/Development/tripwire/spike/threads/v02_gc_safety.nim` (if Task 3.1 authors the REPORT, the source must exist; if source is missing, run the probe first per impl plan Task 3.1 note)
- `nim --version` reports 2.2.x

## Exit Criteria

- All Tasks 3.1 through 3.9 acceptance criteria met, each landed as its own commit on `main`
- All per-task gates passed (TDD for code tasks, completion verify, code review, fact-check)
- `src/tripwire/threads.nim` compiles under `--gc:orc --threads:on` and exposes the full §3.2 surface (`ThreadHandoff` ref type, `tripwireThread[T]`, `runWithVerifier`, `withTripwireThread`, `childEntry`)
- The `withTripwireThread` template's bind list includes ALL identifiers listed in impl plan Task 3.2 (including `getThreadId`, `instantiationInfo`, and the three thread-rejection/leak-defect constructors)
- Compile-time gates fire:
  - `--gc:refc --threads:on` emits `{.error.}` per design §8.1 lines 1300-1304 (F2)
  - `--threads:off` emits `{.error: "tripwireThread requires --threads:on"}` (F1)
- `tests/threads/test_tripwire_thread_basic.nim` passes under `--gc:orc --threads:on --define:tripwireActive --import:tripwire/auto` (happy path, M1)
- `tests/threads/test_tripwire_thread_multi.nim` passes (sequential multi-child, §3.5 blessed pattern, M1)
- `tests/threads/test_tripwire_thread_exception.nim` passes (exception propagation via `joinThread`, E1, M1)
- `tests/threads/test_tripwire_thread_nested_sandbox.nim` passes (nested sandbox inside `withTripwireThread`, E6)
- `tests/threads/test_tripwire_thread_reject_chronos.nim` passes (F4 rejection via `ChronosOnWorkerThreadDefect`, M1b)
- `tests/threads/test_tripwire_thread_reject_nested.nim` passes (E4 rejection via `NestedTripwireThreadDefect`, M1b)
- `tests/threads/test_tripwire_thread_nested_sandbox_spawn.nim` passes (§3.7.1 grandchild-spawn semantics)
- `tests/threads/test_refc_threads_rejected.nim` exists as a negative build test (nimble subtask confirming exit code + stderr contain `tripwireThread requires --gc:orc`)
- `tripwire.nimble` gains matrix cell #7: `exec "nim c --gc:orc --threads:on --define:tripwireActive --define:tripwireUnittest2 --import:tripwire/auto -r tests/all_tests.nim"` plus a negative refc+threads build step
- `spike/threads/v02_gc_safety_REPORT.md` exists with sections: Fixture, orc result, refc result, Reproducer command (per design §8.3)
- `tests/all_tests.nim` is NOT modified in this chunk (aggregation is Task 5.0.5's concern)
- `README.md` is NOT modified in this chunk (threading callout is consolidated in Task 5.5)
- All changes committed to `main` with descriptive commit messages citing design sections
- Metrics achieved: M1 (threading intercepts work under orc), M1b (chronos + nested rejection defects propagate), M-matrix (cell #7 green standalone; fully aggregated in Chunk 5)
- Quality gates passed (comprehensive audit, full test suite, green mirage, fact-check)

## Next

When complete, run the next chunk:
```
Follow the prompt in .claude/prompts/tripwire-v0.2-chunk-4.md
```

Note: Chunk 5 requires BOTH Chunk 3 AND Chunk 4 on `main`. If Chunk 4 was run in parallel and has already merged, you may proceed directly to Chunk 5 (`.claude/prompts/tripwire-v0.2-chunk-5.md`). Verify via `git log --oneline` that WI4 commits are present before invoking Chunk 5.
