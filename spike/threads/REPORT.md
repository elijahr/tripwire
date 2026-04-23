# `--threads:on` verifier inheritance — spike report

Env: Nim 2.2.6 on macOS arm64. All tests built with
`nim c --threads:on -r --hint:all:off <file>.nim`. Each run <1s.

### Q1 — createThread default behavior
File: `q1_create_thread.nim`. Main pushes `test1-main`, calls `target(5)`,
spawns a worker that calls `target(10)` and `target(20)`, joins, calls
`target(6)`.

Observed output:

    [T15302775] TRM fired, verifier: test1-main
    [T15302781] TRM fired, verifier: <NIL>
    [T15302781] TRM fired, verifier: <NIL>
    [T15302775] TRM fired, verifier: test1-main
    test1 main verifier count: 2

- Worker TRM fires against: `<NIL>` (the worker thread's `verifierStack`
  threadvar is a fresh empty seq; threadvars are zero-initialized per thread).
- Main verifier count: **2** (only the two main-thread calls).
- Lost interactions: **yes, 2 of 4** (both worker calls invisible to main's
  verifier). The TRM body ran — the rewrite happened — but `currentVerifier()`
  returned nil, so `inc(v.rewriteCount)` was guarded out. No error, no warning.
  Silently lost.

### Q2 — spawn behavior
File: `q2_spawn.nim`. Same shape via `std/threadpool.spawn`.

    [T15303223] TRM fired, verifier: test2-main
    [T15303235] TRM fired, verifier: <NIL>
    test2 main verifier count: 1
    spawn result: 198

Identical story: worker thread (pool worker, distinct thread id) hits nil
verifier, rewrite still runs (`99*2 == 198`), count lost.

Side note: `std/threadpool` emits a deprecation warning pointing at
`malebolgia`/`taskpools`/`weave`. Relevant because nimfoot v0 docs should
warn about threading at all, not just one API.

### Q3 — nil-verifier Defect guard
File: `q3_defect_guard.nim`. TRM body now `raise newException(Defect, ...)`
when `currentVerifier()` is nil.

    [T15304102] worker about to call target(42)
    /Users/eek/Development/nimfoot/spike/threads/q3_defect_guard.nim(26) workerProc
    Error: unhandled exception: TRM fired on thread T15304102 with no
    active verifier - thread spawned outside test scope? [Defect]
    ---process exit: 1---

- Defect propagates to main: **no** (not as a catchable exception). Main's
  `try/except` around `joinThread` never executes; main's
  "still alive after join" line never prints; `test3 main verifier count`
  never prints.
- What actually happens: an unhandled exception on a non-main thread in
  Nim's default thread runtime calls the unhandled-exception hook which
  writes to stderr and `quit(1)`s the entire process. From the test
  runner's perspective this is a hard crash with a readable stack.
- Practically usable for catching this: **yes, loudly.** The test
  terminates with a stack trace naming the worker proc. This is a better
  failure mode than silent loss, but:
  - You get no partial results from the run (main never finishes its
    assertions).
  - You can't `try/except` it in a test harness to mark one case failed
    and continue — the whole process dies.
  - The crash surfaces even if the user *expects* their worker thread to
    touch mocked code (e.g. testing a producer/consumer pair).

### Q4 — Inherited verifier wrapper
File: `q4_inherit.nim`. Wrapper `nimfootThread(addr handoff)` pre-allocates
a `Handoff` struct in `{.global.}` storage, passes a `ptr Handoff` to the
child, which pushes a verifier named `inherited:<parent>` on its own
threadvar stack, runs user work, pops, and under lock writes its count
back into the handoff. Parent folds `handoff.childCount` into its own
verifier on join.

    [T15304434] TRM fired, verifier: test4-main
    [T15304460] TRM fired, verifier: inherited:test4-main
    [T15304460] TRM fired, verifier: inherited:test4-main
    [T15304460] TRM fired, verifier: inherited:test4-main
    test4 main verifier count (after fold): 4
    child recorded: 3
    expected total: 4 (1 main + 3 child)

- Works: **yes** for the simple counter case. Rewrites fire against a
  labeled inherited verifier on the child, and counts fold back into the
  parent on join.
- What's lost / what it costs:
  - **Only works if the user opts in** by writing `nimfootThread` instead
    of `createThread`. Any stray `createThread`/`spawn`/`std/tasks` still
    hits nil. Doesn't help with third-party code that spins its own
    threads (timers, HTTP clients, thread pools inside libraries).
  - **Only counters fold cleanly.** A real verifier holds ordered call
    logs, argument captures, `expectOnce`/`expectTimes` state, strict/lax
    mode flags, etc. Merging two event logs across a join requires either
    a total order (which we don't have — interleaving on the child is lost
    by the time we fold) or a decision to present the child as an opaque
    sub-transcript. Either is a nontrivial design call, not a "just copy
    the int" fix.
  - **GC-safety cliff.** Passing the parent `Verifier` ref directly into
    the child thread is not gcsafe on ORC without `--threads:on`
    discipline (or ARC + deepCopy). This spike sidestepped it by copying
    the name string into a `{.global.}` POD struct. A real implementation
    has to decide: deep-copy verifier config to the child? share with a
    lock? isolate the child's verifier and reconcile on join? Each is a
    noticeable API surface.
  - **Doesn't compose with spawn/FlowVar.** `nimfootThread` is a
    `createThread` wrapper; spawning into the stdlib threadpool (or
    malebolgia, taskpools, weave) needs a parallel wrapper per library.
    That's more surface than v0 wants.
- Worth implementing in v0: **no.** The primitive works, but the cost to
  make it robust (log merging semantics, gcsafe verifier transport,
  per-threading-library wrappers) is well beyond a 1.0 budget.

### Recommendation for nimfoot v0

**Option (a) with guardrail**, specifically:

1. Document "threaded user code under test is unsupported in v0." Put this
   in the README and the `nimfoot.verify` docstring.
2. Ship the nil-verifier Defect guard from Q3 as the default behavior.
   When a TRM fires on a thread that has no verifier on its stack, raise
   `Defect` with the thread id and a message pointing at the threading
   limitation. This turns the silent-loss failure mode (Q1/Q2) into a
   loud, debuggable crash — which is strictly better than the status quo
   and costs roughly five lines of runtime code.
3. Do **not** ship `nimfootThread` in v0. Q4 shows the primitive is
   feasible, but the surface area to make it complete (log merging,
   gcsafe transport, wrappers for spawn/taskpools/weave) belongs in v0.2
   or later, driven by a real user request rather than speculative
   design.

Net: option (a) plus the defect guard. Option (b) is a v0.2 candidate.
Option (c) ("defer threading entirely") is effectively what (a) already
achieves — there's no additional code to suppress; threading just isn't
supported, and the guard makes misuse obvious.

One sharper note on the guard: because an unhandled exception on a worker
thread `quit(1)`s the process (Q3), the message needs to include the
thread id and a URL/tag to the "threading unsupported" docs section, so a
confused user isn't left staring at `Defect: TRM fired on thread T...`
with no idea what to do. That's a docstring/message edit, not an
architectural change.

Confidence: **high** for Q1/Q2/Q3 observed behavior (reproducible, matches
Nim's documented threadvar and unhandled-exception semantics). **Medium**
for the Q4 "not worth it" call — it's a judgment on scope, not on
feasibility; a user with a concrete threaded-test use case could change
the calculus.
