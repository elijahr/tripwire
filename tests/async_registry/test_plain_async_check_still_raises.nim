## tests/async_registry/test_plain_async_check_still_raises.nim —
## Task 4.6 REGRESSION GUARD (impl plan lines 833, 842; design §4.5).
##
## Invariant under guard: when a `tripwire.test:` body uses plain
## `asyncCheck` (NOT `asyncCheckInSandbox`), the pending op IS NOT
## drained by the template (plain `asyncCheck` bypasses the registry),
## and the template's `hasPendingOperations()` gate MUST fire,
## raising `PendingAsyncDefect` on teardown.
##
## Expected status: PASS BOTH before and after Task 4.6's ordering
## change (drain -> poll(0) -> hasPending -> verifyAll). Its job is
## to catch a future refactor that accidentally silences the
## unconditional teardown check on plain `asyncCheck`. Not a RED->GREEN
## target — a permanent invariant guard.
##
## Why direct invocation (not `tripwire.test "name":` nested inside
## `std_ut.test`): the backend (`std/unittest.test`) catches all
## exceptions in its body and records them as test failures rather
## than letting them escape. So `expect PendingAsyncDefect:` wrapping
## a nested `tripwire.test` cannot observe the defect — the backend
## swallows it before `expect` sees anything. The established pattern
## for defect-observing integration_unittest tests is direct
## invocation of the template's expansion (see
## `tests/test_integration_unittest.nim` lines 66-79 for the same
## shape applied to `UnusedMocksDefect`).
##
## The manual expansion below mirrors the POST-ordering-change
## template body (design §4.5): body -> drainPendingAsync(v) ->
## poll(timeout = 0) -> hasPending -> raise. Against pre-change code
## the extra `drainPendingAsync` / `poll(0)` calls are no-ops on this
## test's inputs (empty registry since plain `asyncCheck` doesn't
## register; `sleepAsync(20)` is still pending after `poll(0)`), so
## the test passes unchanged. This gives us the "passes both before
## and after" behavior the impl plan requires.
##
## Consumer-import requirement (design §4.1 line 724): modules that
## touch `Future[T]` at the call site MUST `import std/asyncdispatch`.
import std/[unittest as std_ut, asyncdispatch]
import tripwire/[sandbox, verify, errors, futures, integration_unittest]

std_ut.suite "plain asyncCheck regression guard":
  setup:
    # Start each test with an empty verifier stack so a leak from a
    # prior test can't make this one pass for the wrong reason.
    # `setup` is a bare identifier injected by std/unittest's `suite`
    # template (not qualified by the `std_ut` alias).
    while currentVerifier() != nil:
      discard popVerifier()

  std_ut.test "plain asyncCheck in test: body raises PendingAsyncDefect via teardown gate":
    # Hold `fut` in the test's scope so we can drain it AFTER the
    # expected defect raises. Without this, the plain-asyncCheck
    # callback stays in asyncdispatch's global queue and pollutes
    # subsequent tests.
    var fut: Future[int]

    proc leaker(): Future[int] {.async.} =
      await sleepAsync(20)
      return 42

    # Direct invocation of the `tripwire.test:` template's expansion
    # (post-§4.5 ordering). Mirrors integration_unittest.nim lines
    # 80-90 after Task 4.6 lands. Against pre-Task-4.6 code the extra
    # `drainPendingAsync`/`poll(0)` are no-ops on this input.
    let testName = "inner_plain_asyncCheck_leak"
    var raised: ref PendingAsyncDefect = nil
    try:
      let nfV = pushVerifier(newVerifier(testName))
      try:
        # === body under test ===
        fut = leaker()
        asyncCheck fut     # PLAIN asyncCheck — not registered with nfV
        # === end body ===

        # Post-§4.5 ordering: drain first (no-op here — empty
        # registry), then one guarded poll flush, then the gate.
        # The poll must be guarded by `hasPendingOperations()` because
        # `asyncdispatch.poll` raises `ValueError` on an empty
        # dispatcher — the real template at integration_unittest.nim:96
        # applies the same guard for the same reason.
        drainPendingAsync(nfV)
        if futures.hasPendingOperations():
          poll(timeout = 0)
        if futures.hasPendingOperations():
          raise newPendingAsyncDefect(testName)
      finally:
        discard popVerifier()
        # Skip verifyAll — we are asserting the gate, not verifier
        # state, and `getCurrentException() != nil` is the template's
        # own condition for skipping verifyAll here.
    except PendingAsyncDefect as e:
      raised = e

    # Drive the dispatcher to completion so the plain-asyncCheck
    # callback clears out of the process-global queue before the next
    # test runs.
    discard waitFor fut

    # The gate MUST have fired. Full-field assertion against the exact
    # defect constructor (errors.nim lines 142-146) so a drift in the
    # template's raise-site (wrong `name` passed, wrong constructor)
    # regresses this test rather than silently passing.
    std_ut.check raised != nil
    let expectedMsg = "test '" & testName &
      "' ended with pending async operations." &
      "\nUse `waitFor` to drain futures, or -d:tripwireAllowPendingAsync to" &
      " suppress." &
      "\n(tripwire intercepts Nim source calls only. " &
      "FFI ({.importc.}, {.dynlib.}, {.header.}) is not intercepted in v0. " &
      "See docs/concepts.md#scope.)"
    std_ut.check raised.msg == expectedMsg
    std_ut.check raised.testName == testName
    # Future body ran once waitFor drove it to completion (proves the
    # Future was genuinely pending at gate time, not already resolved).
    std_ut.check fut.finished
    std_ut.check not fut.failed
    std_ut.check fut.read == 42
