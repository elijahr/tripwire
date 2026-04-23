# Async lifetime / asyncCheck leak — spike report

Env: Nim 2.2.6 on macOS arm64. `nim c -r --hint:all:off <file>.nim`. Wall
time per file <3s. Stdlib `asyncdispatch` (chronos not tested — previous
async spike showed same call-site semantics; lifetime behavior is a
dispatcher property, no reason to expect divergence, noted as follow-up).

## Q1 — asyncCheck leak default behavior

File: `q1_async_leak.nim`. test1 pushes v1, launches `asyncCheck
asyncDelayedTarget()` (sleeps 50ms then calls `target()`), pops v1.
test2 pushes v2, immediately pops v2 (empty body). Then `poll(200)`.

- TRM fired against: **`<NIL>`** (stack was empty when the callback resumed).
- test2 contamination: **no** in this scenario (test2 had already popped).
- Stack state: clean, depth=0.
- Outcome: (b) **silent miss** — the TRM body's `if v != nil` branch skipped
  the increment. No crash, no error, nothing recorded. Leaked TRMs without a
  guard just silently do nothing useful.

## Q2 — waitFor control case

File: `q2_waitfor_control.nim`. `waitFor asyncDelayedTarget()` inside the
test body.

- Works as expected: **yes**, `safe.rewriteCount=1`, returned value 14,
  stack drained cleanly.

## Q3 — nil-verifier guard raising Defect

File: `q3_nil_guard.nim`. Same leak shape as Q1, but TRM raises Defect on
nil stack. `poll()` wrapped in try/except.

- Leaked TRM raised: **yes**.
- Where the exception went: **it escaped `poll()`** as a `Defect` with a
  Nim `Async traceback:` attached, pointing to the poll call site. It did
  NOT get swallowed by asyncCheck's default handler. Caught cleanly by
  `except Defect`.
- Practically usable as a tripwire: **yes, with caveats**. Works if the
  test runner owns the dispatcher drain and wraps it. But it only fires
  when the stack is empty at TRM time. It does NOT catch Q4's cross-test
  contamination (next section).

## Q4 — generation counter / cross-test contamination

File: `q4_generation.nim`. test1 leaks a 40ms async; test2 holds its
verifier on the stack for 80ms via `waitFor sleepAsync(80)`. The leak's
TRM fires while test2's verifier is still current.

- Leaked TRM hit: **test2's verifier** (`v.name=A2 gen=2`). test1's
  verifier (gen=1) shows `count=0`. test2 shows `count=1`. **Test isolation
  broken — outcome (c).**
- Detectability via generation counter on Verifier: **no**. The TRM only
  consults the stack top. At fire time, the stack top IS a live, valid,
  current-generation verifier. There is no local signal that the fire came
  from a leaked coroutine vs. legitimate test2 code. The "popped-but-
  referenced" idea only works if the leaked closure itself captured a
  reference to the original verifier — but a stack-based `currentVerifier()`
  lookup resolves at TRM fire time, not at closure creation. Nimfoot cannot
  force user async closures to pin their verifier at spawn.

  The only way to recover this is a generation token carried THROUGH the
  async context (e.g., per-dispatcher scoped state, or instrumenting the
  test template to snapshot a generation and wedge it into a comparison at
  TRM fire). That is heavy machinery and would need its own spike.

## Recommendation for nimfoot v0

**Combination (d), weighted toward (a) + (b):**

1. **(b) Nil-verifier Defect guard** — cheap, catches the common leak
   shape where the dispatcher drains between tests. Already proven to
   escape `poll()` with a usable async traceback. Ship it.
2. **(a) Document asyncCheck as unsupported** — explicit policy: any
   async launched during a test must be awaited (via `waitFor`) before
   the test body returns. State this in the test template docstring and
   the README's "async" section.
3. **Drain-and-warn at test teardown** — the test template, immediately
   after the user body but before `popVerifier()`, checks
   `hasPendingOperations()`. If true, emit a clear error naming the test
   and suggesting `waitFor`. This catches the Q4 poison case *before* the
   next test starts. Concretely:

        template test*(name: string, body: untyped) =
          let v = pushVerifier(name)
          try:
            body
            if hasPendingOperations():
              raise newException(Defect,
                "Test '" & name & "' ended with pending async operations. " &
                "Use waitFor or await the future explicitly.")
          finally:
            discard popVerifier()
            v.verifyAll()

   This converts Q4's silent cross-test contamination into a loud,
   test-scoped error at the guilty test's boundary.
4. **Skip (c) generation counter for v0.** The detection it provides
   duplicates what (3) already catches, with much more runtime machinery.
   Revisit if users report real-world leaks that (3) misses (e.g., timers
   that schedule beyond test boundaries by design).

Residual risk: users who legitimately need cross-test background async
(pooled clients, long-lived timers) will hit (3)'s guard. Escape hatch:
a `test` variant that skips the pending-ops check, or an explicit
`nimfoot.allowPendingAsync()` call inside the body. Out of scope for this
spike; note for v0 design.

Files: `q1_async_leak.nim`, `q2_waitfor_control.nim`, `q3_nil_guard.nim`,
`q4_generation.nim` under `/Users/eek/Development/nimfoot/spike/asynclife/`.
