## tests/async_registry/test_async_check_generation_repro.nim — Task 4.3b
## Ports spike/asynclife/q4_generation.nim:70-99 (the testA1 -> testA2
## cross-test contamination sequence) to a v0.2 regression test. Pairs
## with tests/async_registry/test_async_check_leak_repro.nim (Task 4.3,
## the q1 in-test leak reproducer). The two reproducers together cover
## both in-scope leak modes that motivated the v0.2 helper:
##
##   * q1_async_leak: Future leaks past sandbox exit; pending-ops
##     observable at teardown.
##   * q4_generation: Future leaks from sandbox A into sandbox B's
##     window; the Future's body observes the WRONG verifier
##     (`currentVerifier()` returns B's verifier while A's Future
##     body runs) — the cross-test contamination pattern.
##
## The v0.2 story: plain `asyncCheck` STILL produces this contamination
## (M2b honesty check — this failure mode is not fixed automatically;
## the user must opt in). Switching to `asyncCheckInSandbox` +
## `drainPendingAsync(currentVerifier())` inside A's sandbox blocks A's
## exit until the Future completes, so the Future body runs while A's
## verifier is still current — no leak reaches B.
##
## Recording the contamination signal: `sandbox:` (sandbox.nim line 38)
## does NOT take a name argument — it creates an anonymous verifier via
## `newVerifier()`. Rather than a string name, we record verifier
## IDENTITY via the `Verifier` ref pointer (`Verifier* = ref object` at
## sandbox.nim line 7, so `==` is pointer equality). We snapshot v1 and
## v2 by grabbing `currentVerifier()` at the top of each sandbox body;
## the async body records the `currentVerifier()` it observes at resume
## time; the test then compares pointers to determine which verifier
## was live when the Future's body ran.
##
## Chronos-aware pending-ops wrapper: this test imports
## `tripwire/futures` so the inline pending-ops check resolves to
## tripwire's chronos-aware wrapper (src/tripwire/futures.nim lines
## 41-53), NOT the plain `std/asyncdispatch.hasPendingOperations`. We
## use EXPLICIT QUALIFICATION `futures.hasPendingOperations()`
## everywhere the check appears — without qualification the name binds
## to stdlib (imported for `asyncCheck`/`sleepAsync`/`waitFor`/
## `Future[T]`) and misses chronos pending work under `-d:chronos
## -d:chronosFutureTracking`. See test_async_check_leak_repro.nim lines
## 30-38 for the same rationale.

import std/[unittest, asyncdispatch]
import tripwire/[sandbox, verify, async_registry, errors, futures]

suite "q4_generation port":
  setup:
    # Drain any verifiers left by earlier tests so each test runs with
    # an empty stack.
    while currentVerifier() != nil:
      discard popVerifier()

  test "plain asyncCheck leaks into next sandbox's window (M2b honesty)":
    # RED shape (spike q4_generation.nim lines 70-99):
    #   * sandbox A1 body pushes v1 via sandbox:, spawns a Future via
    #     plain `asyncCheck` that awaits sleepAsync(40) then records
    #     `currentVerifier()` — the signal — into `observedVerifier`.
    #   * A1's sandbox body returns BEFORE the Future completes (body
    #     does not yield, does not drain).
    #   * Immediately, sandbox A2 body pushes v2 and does
    #     `waitFor sleepAsync(80)`, holding v2 on the stack long enough
    #     for A1's leaked Future to resume inside A2's window.
    #   * When the Future resumes, `currentVerifier()` returns v2
    #     (cross-test contamination observed).
    var observedVerifier: Verifier = nil
    var v1, v2: Verifier = nil
    var fut: Future[int]

    proc leaker(): Future[int] {.async.} =
      await sleepAsync(40)
      # Signal: record whichever verifier is live at resume time.
      # Under plain asyncCheck this is v2 (A2's verifier), because A1
      # has already popped and A2 is blocking inside waitFor.
      observedVerifier = currentVerifier()
      return 1

    # Sandbox A1 — testA1 analogue.
    sandbox:
      v1 = currentVerifier()
      fut = leaker()
      asyncCheck fut  # plain asyncCheck — the leak vector.
      # Body returns immediately; fut is still pending, and
      # `sandbox:` is about to pop v1.

    # Sandbox A2 — testA2 analogue. Holds v2 on the stack for 80ms,
    # which is longer than leaker's 40ms sleep, so the leaked Future
    # resumes WHILE v2 is current.
    sandbox:
      v2 = currentVerifier()
      # waitFor drives the dispatcher while v2 is on the stack.
      # During this window, `leaker`'s sleep expires and its body
      # resumes — and calls `currentVerifier()`, which returns v2.
      waitFor sleepAsync(80)

    # Drive the dispatcher to completion so `fut` and any internal
    # asyncCheck callbacks are cleared. Without this, a subsequent
    # test in the same suite would inherit a dirty dispatcher state.
    # Skip if no pending ops remain (the leaker completed inside A2's
    # waitFor window).
    if futures.hasPendingOperations():
      discard waitFor fut

    # Contamination signal: the Future's body ran while v2 was the
    # current verifier, not v1 (the verifier that was live at spawn
    # time). This is the failure mode v0.2 does NOT fix without
    # opt-in — plain asyncCheck remains unsafe.
    check v1 != nil
    check v2 != nil
    check v1 != v2  # sandbox: creates a fresh verifier each time
    check observedVerifier == v2  # contamination: wrong verifier
    check observedVerifier != v1

  test "asyncCheckInSandbox + drain contains Future within its own sandbox":
    # GREEN shape: same two-sandbox sequence, but A1's body uses
    # `asyncCheckInSandbox(fut)` and then `drainPendingAsync(
    # currentVerifier())` BEFORE `sandbox:` pops v1. The drain blocks
    # A1 until the Future completes — inside A1's sandbox, where
    # `currentVerifier()` IS v1. So the Future's body records v1, not
    # v2. No leak reaches A2's window.
    var observedVerifier: Verifier = nil
    var v1, v2: Verifier = nil

    proc contained(): Future[int] {.async.} =
      await sleepAsync(40)
      # Signal: under asyncCheckInSandbox + drain, this runs while v1
      # is still the current verifier (drain blocks A1's exit).
      observedVerifier = currentVerifier()
      return 1

    sandbox:
      v1 = currentVerifier()
      let fut = contained()
      asyncCheckInSandbox(fut)
      # Explicit drain: blocks A1 until `fut` completes. Task 4.6
      # will wire this into the `test:` template automatically; until
      # then, the opt-in helper requires an explicit drain call.
      drainPendingAsync(currentVerifier())
      # Inside the sandbox body, after drain, the Future must have
      # finished and its body must have recorded v1.
      check fut.finished
      check not fut.failed
      check observedVerifier == v1

    sandbox:
      v2 = currentVerifier()
      # No leak to observe here — A1's drain consumed the Future.
      # waitFor gives any leaked Future (there isn't one in the GREEN
      # path) a chance to resume, proving containment held.
      waitFor sleepAsync(80)

    # Post-sandbox invariants: no leftover pending ops; the observed
    # verifier is v1 (containment held), not v2 (contamination).
    check not futures.hasPendingOperations()
    check v1 != nil
    check v2 != nil
    check v1 != v2
    check observedVerifier == v1
    check observedVerifier != v2
