## tests/async_registry/test_async_check_leak_repro.nim — Task 4.3
## Ports spike/asynclife/q1_async_leak.nim (entire file, specifically
## the leak pattern at lines 43-57 of the spike) to a v0.2 regression
## test. Demonstrates that:
##   (a) plain asyncCheck STILL leaks a pending op past sandbox exit
##       and raises PendingAsyncDefect at teardown — M2b honesty check
##       (plain asyncCheck was and remains unsafe; this invariant will
##       be codified in Task 4.6's regression guard);
##   (b) asyncCheckInSandbox + drainPendingAsync(currentVerifier())
##       prevents the leak by draining before sandbox exit.
##
## Honesty-check shape: `sandbox:` (the template in sandbox.nim) does
## NOT itself check `hasPendingOperations()` on exit — only
## `tripwire/integration_unittest.test:` does (integration_unittest.nim
## lines 84-86). We use `std/unittest` here (not tripwire.test) to keep
## the reproducer independent of Task 4.6's wiring and to exercise the
## invariant explicitly: the test performs the same post-sandbox
## pending-op check inline and raises `PendingAsyncDefect` if the leak
## persists. Once Task 4.6 lands and integration_unittest.test is the
## default entry point for tripwire tests, the GREEN test in (b) can
## drop the explicit `drainPendingAsync` call — the wrapping `test:`
## template will run it automatically.
##
## Consumer-import requirement (design §4.1 line 724): modules that
## invoke `asyncCheckInSandbox` MUST also `import std/asyncdispatch`
## so that `Future[T]` resolves at the call site, even though the
## template `bind`s `asyncCheck` from the library module.
##
## Chronos-aware pending-ops wrapper: this test imports
## `tripwire/futures` so the inline `hasPendingOperations()` call at
## the sandbox-exit honesty check resolves to tripwire's chronos-aware
## wrapper (src/tripwire/futures.nim lines 41-53), NOT the plain
## `std/asyncdispatch.hasPendingOperations`. Without this import the
## name would bind to the stdlib proc and miss chronos pending work
## under `-d:chronos -d:chronosFutureTracking`. Task 4.6's
## `integration_unittest.test:` wiring uses the same wrapper; keeping
## parity here ensures the inline honesty check in this reproducer
## tracks the real invariant.

import std/[unittest, asyncdispatch]
import tripwire/[sandbox, verify, async_registry, errors, futures]

suite "q1_async_leak port":
  setup:
    # Drain any verifiers left by earlier tests so each test runs
    # with an empty stack.
    while currentVerifier() != nil:
      discard popVerifier()

  test "plain asyncCheck still leaks and raises at teardown (M2b honesty)":
    # RED shape (spike q1_async_leak.nim lines 43-57): sandbox body spawns
    # a Future via plain `asyncCheck`; the Future awaits `sleepAsync(20)`
    # then mutates a counter (stand-in for a mockable proc — a simple
    # counter mutation is sufficient to prove the Future body ran; the
    # acceptance criterion is about drain semantics, not TRM fire-site
    # routing). Sandbox body returns BEFORE the sleep completes, so the
    # Future is still pending when `sandbox:` pops its verifier. The
    # honesty check: `hasPendingOperations()` must return true after the
    # sandbox exits, and the test raises `PendingAsyncDefect` to assert
    # the leak.
    var counter = 0
    var fut: Future[int]

    proc leaker(): Future[int] {.async.} =
      await sleepAsync(20)
      inc counter
      return counter

    sandbox:
      fut = leaker()
      asyncCheck fut   # plain asyncCheck — the leak vector
      # body returns immediately; fut is still pending.
      # Do NOT reduce sleepAsync(20) to 0 or remove it — the body must
      # yield so `sandbox:` pops before `fut` completes. Without a yield,
      # `fut` resolves synchronously and the leak becomes unobservable.

    # After sandbox exit: the leak must still be observable. This is the
    # v0.1 behavior that v0.2 preserves for plain asyncCheck (the opt-in
    # `asyncCheckInSandbox` is the safe path).
    var raised: ref PendingAsyncDefect = nil
    if futures.hasPendingOperations():
      raised = newPendingAsyncDefect("q1_async_leak_repro")

    # Clean up the dispatcher's pending callback so this test does not
    # leak into the next one. `waitFor fut` drives the dispatcher until
    # the Future resolves; this is the test-scope analogue of
    # drainPendingAsync but without needing a verifier on the stack
    # (the sandbox has already popped).
    discard waitFor fut

    # The honesty check: plain asyncCheck MUST have left a pending op
    # observable at the moment of sandbox exit. If not, either sandbox:
    # silently drained (it should not — Task 4.6 is not landed) or the
    # dispatcher's pending-ops accounting changed under us.
    check raised != nil
    # Full message comparison: assert the EXACT shape produced by
    # `newPendingAsyncDefect(testName)` (errors.nim lines 142-146).
    # Constructed here so a drift in either the template or the footer
    # regresses this assertion rather than silently passing.
    let expectedMsg = "test 'q1_async_leak_repro' ended with pending async operations." &
      "\nUse `waitFor` to drain futures, or -d:tripwireAllowPendingAsync to" &
      " suppress." &
      "\n(tripwire intercepts Nim source calls only. " &
      "FFI ({.importc.}, {.dynlib.}, {.header.}) is not intercepted in v0. " &
      "See docs/concepts.md#scope.)"
    check raised.msg == expectedMsg
    check raised.testName == "q1_async_leak_repro"
    # Future body did run once waitFor drove it to completion.
    check counter == 1

  test "asyncCheckInSandbox + explicit drain completes cleanly":
    # GREEN shape: same spawn pattern as the RED test, but using
    # `asyncCheckInSandbox(fut)` (which registers `fut` with
    # `currentVerifier().futureRegistry`) followed by an explicit
    # `drainPendingAsync(currentVerifier())` inside the sandbox body.
    # Drain must run BEFORE sandbox exits so Task 4.6's wiring is not
    # a precondition for this test. After Task 4.6 lands, the wrapping
    # `test:` template (integration_unittest.nim) will drain for us and
    # the explicit `drainPendingAsync` call below can be removed.
    var counter = 0

    proc drained(): Future[int] {.async.} =
      await sleepAsync(20)
      inc counter
      return counter

    sandbox:
      let fut = drained()
      asyncCheckInSandbox(fut)
      # Explicit drain (Task 4.6 pre-wiring workaround; see file header).
      drainPendingAsync(currentVerifier())
      # By this point, drain has polled until the Future completed.
      # Assert inside the body so the sandbox teardown sees a clean
      # verifier (no timeline interactions, no mocks — verifyAll is a
      # no-op).
      check fut.finished
      check not fut.failed
      check counter == 1

    # After sandbox exit: no leak, no pending ops. Compare to the RED
    # test's `hasPendingOperations()` check — the whole point of the
    # opt-in helper is that this must be false here.
    check not futures.hasPendingOperations()
    check counter == 1
