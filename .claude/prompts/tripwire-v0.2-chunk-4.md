# Tripwire v0.2 — Chunk 4/5: asyncCheckInSandbox + Future registry (WI4)

## Working Directory

**Path:** `/Users/eek/Development/tripwire`
**Branch:** `main`

BEFORE ANY WORK:
1. `cd /Users/eek/Development/tripwire && pwd && git branch --show-current`
2. Verify output shows `main`
3. ALL file paths must be absolute, rooted at `/Users/eek/Development/tripwire`
4. Do NOT create new branches or switch branches (trunk-based; session preference `worktree: none`)

## Context

This chunk lands Work Item 4 of Tripwire v0.2: the opt-in async-Future tracking mechanism. It creates `src/tripwire/async_registry.nim` (`asyncCheckInSandbox[T]`, `withAsyncSandbox`), adds `drainPendingAsync` to `verify.nim` with per-Future spawn-site diagnostics and a 5000ms default deadline (`-d:tripwireAsyncDrainTimeoutMs:N` to override), wires the drain into `integration_unittest.test` template ordering (drain → poll(0) → hasPending → verifyAll per design §4.5), and ports two motivating spike reproducers (`q1_async_leak`, `q4_generation`) as regression tests. Chronos Futures are rejected at compile time via `{.warning.}`.

Previous chunks completed: Chunk 1 (WI1 — FFI audit auto-discovery) and Chunk 2 (WI2 — Shared Verifier field + error types). Chunk 3 (WI3) may also be in flight or already landed, depending on whether sessions ran in parallel; WI3 and WI4 are structurally independent and may be merged in either order.

## Execution

**MANDATORY: You MUST invoke the `develop` skill using the Skill tool before doing ANY work.**

```
Skill tool call:
  skill: "develop"
  args: "Escape hatch: impl plan at /Users/eek/.local/spellbook/docs/Users-eek-Development-tripwire/plans/2026-04-23-tripwire-v0.2-impl.md, treat as ready. Tasks 4.1-4.7 (including 4.3b) (Work Item 4). Fully autonomous."
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
- Task 4.1 (`async_registry.nim`): full RED→GREEN cycle; template uses `mixin currentVerifier` (NOT bind) per §4.1 line 576 and binds `RegisteredFuture, FutureBase, newLeakedInteractionDefect, getThreadId, instantiationInfo, asyncCheck, stderr`.
- Task 4.2 (`drainPendingAsync` in `verify.nim`): uses the WI2 `newPendingAsyncDefect(msg, parent)` overload for parent-chain propagation.
- Task 4.3 / 4.3b: port spike reproducers `spike/asynclife/q1_async_leak.nim` and `spike/asynclife/q4_generation.nim:76-88` respectively.
- Task 4.6 (integration_unittest ordering change): `test_plain_async_check_still_raises.nim` is a REGRESSION GUARD (expected to PASS before AND after) — NOT a RED→GREEN target. Also extend the `integration_unittest.nim:74-76` bind list to include `drainPendingAsync`.
- Task 4.7 (chronos rejection): compile-time `{.warning.}` test via `staticExec` or `when compiles(...)` probe.
- `tests/all_tests.nim` is NOT modified in this chunk (aggregation is Task 5.0.5's concern).

### Post-All-Tasks Gates (mandatory, end of this chunk)

After all tasks in this chunk pass per-task gates:

1. Comprehensive implementation audit (4.6.1) — inline audit prompt
2. Full test suite (4.6.2) — dispatch subagent to run `nimble test` covering cells 1-6 (every cell must still be green; cell #5 orc+chronos is the load-bearing regression cell for Task 4.6's ordering change); invoke each new `tests/async_registry/*.nim` module standalone to verify it passes (aggregated verification lands in Chunk 5)
3. Green mirage audit (4.6.3) -> must invoke `auditing-green-mirage` skill using the Skill tool
4. Comprehensive fact-checking (4.6.4) -> must invoke `fact-checking` skill using the Skill tool

## Pre-conditions

- Chunk 2 committed to `main` (required). Verify:
  - `git log --oneline` shows WI2 commits (see Chunk 3's pre-conditions for the list)
  - `git grep 'futureRegistry' src/tripwire/sandbox.nim` returns the field declaration
  - `src/tripwire/async_registry_types.nim` exists with `RegisteredFuture` type
  - `git grep 'newPendingAsyncDefect\*' src/tripwire/errors.nim` shows BOTH the one-argument form AND the `(msg, parent)` overload
- `git status` clean on `main`
- `nimble test` passes (6 cells if Chunk 3 hasn't merged yet; 7 cells if Chunk 3 is already on `main`)
- `nim --version` reports 2.2.x
- Spike reproducer source files exist at `/Users/eek/Development/tripwire/spike/asynclife/q1_async_leak.nim` and `/Users/eek/Development/tripwire/spike/asynclife/q4_generation.nim` (referenced by Tasks 4.3 and 4.3b)

## Exit Criteria

- All Tasks 4.1, 4.2, 4.3, 4.3b, 4.4, 4.5, 4.6, 4.7 acceptance criteria met, each landed as its own commit on `main` (8 commits total)
- All per-task gates passed (TDD for RED-target tasks, completion verify, code review, fact-check)
- `src/tripwire/async_registry.nim` exposes `asyncCheckInSandbox[T]` (registers a `RegisteredFuture` on `currentVerifier().futureRegistry`, calls `asyncCheck`, raises `LeakedInteractionDefect` if no verifier, emits 10_000-entry stderr diagnostic per §4.1 lines 593-597) and `withAsyncSandbox` (pure readability shim)
- `async_registry.nim` imports `async_registry_types` for `RegisteredFuture` (DR1 cross-check — dependency graph `sandbox -> async_registry_types <- async_registry` is acyclic)
- `src/tripwire/verify.nim` gains `tripwireAsyncDrainTimeoutMs` `{.intdefine.}` constant (default 5000) AND `drainPendingAsync*(v: Verifier)` proc per design §4.4 lines 656-729
  - Deadline-capped `asyncdispatch.poll` loop
  - On timeout: raises `PendingAsyncDefect` with per-Future spawn-site diagnostic listing ALL un-drained futures
  - Mid-drain Future failure: wraps as `PendingAsyncDefect(parent=...)` using the WI2 overload
  - Existing `verifyAll` remains sync and unchanged
- `src/tripwire/integration_unittest.nim:85-86` `test` template ordering is drain → poll(0) → hasPending → verifyAll (per §4.5); bind list at lines 74-76 extended to include `drainPendingAsync`
- `tests/async_registry/test_async_check_leak_repro.nim` passes — ports `spike/asynclife/q1_async_leak.nim`; GREEN under `asyncCheckInSandbox` (M2)
- `tests/async_registry/test_async_check_generation_repro.nim` passes — ports `spike/asynclife/q4_generation.nim:76-88`; cross-test contamination prevented (M2, M2b secondary)
- `tests/async_registry/test_async_check_basic.nim` passes — E3 happy path drains before `verifyAll` (M2)
- `tests/async_registry/test_async_check_drain_timeout.nim` passes — E7 timeout raises `PendingAsyncDefect` with per-Future spawn-site diagnostic for ALL un-drained futures (M2)
- `tests/async_registry/test_plain_async_check_still_raises.nim` passes — REGRESSION GUARD: plain `asyncCheck` still raises `PendingAsyncDefect` at teardown in v0.2 exactly as in v0.1 (M2b honesty check)
- `tests/async_registry/test_chronos_future_rejected.nim` passes — compile-time `{.warning.}` fires, Future NOT registered (M3b secondary — chronos rejection at compile time)
- `tests/all_tests.nim` is NOT modified in this chunk
- Cell #5 (orc+chronos) stays green after the ordering change
- All changes committed to `main` with descriptive commit messages citing design sections
- Metrics achieved: M2 (async registry works end-to-end), M2b (plain `asyncCheck` honesty check + generation-leak prevention), M3b partial (chronos Future compile-time warning)
- Quality gates passed (comprehensive audit, full test suite, green mirage, fact-check)

## Next

When complete, run the next chunk:
```
Follow the prompt in .claude/prompts/tripwire-v0.2-chunk-5.md
```

Note: Chunk 5 requires BOTH Chunk 3 AND Chunk 4 on `main`. If Chunk 3 hasn't merged yet (parallel-session scenario), wait for WI3 commits to land and `nimble test` to pass before starting Chunk 5. Verify via `git log --oneline | grep -E 'tripwireThread|matrix cell' | head -5` that WI3 commits are present.
