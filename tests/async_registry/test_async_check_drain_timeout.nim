## tests/async_registry/test_async_check_drain_timeout.nim —
## Task 4.2 RED/GREEN test. Verifies that `drainPendingAsync`
## raises `PendingAsyncDefect` when a registered Future has not
## finished within `tripwireAsyncDrainTimeoutMs` (design §4.4
## lines 655-729, impl plan Task 4.2 line 748, anchors Task 4.5
## per impl plan line 748 note).
##
## Compile-time override: this test assumes
## `-d:tripwireAsyncDrainTimeoutMs:50` is on the `nim c`
## command line so drain hits its cap inside ~50ms rather
## than the 5s default. `tripwireAsyncDrainTimeoutMs` is a
## `const {.intdefine.}` and cannot be re-assigned at runtime.
##
## Consumer-import requirement (impl plan line 724): modules that
## invoke `asyncCheckInSandbox` MUST also `import std/asyncdispatch`
## so that `Future[T]` resolves at the call site, even though the
## template `bind`s `asyncCheck` from the library module.
import std/[unittest, asyncdispatch, os, strutils]
import tripwire/[sandbox, verify, async_registry, errors]

suite "drainPendingAsync timeout":
  setup:
    # Drain any verifiers left by earlier tests so each test runs
    # with an empty stack.
    while currentVerifier() != nil:
      discard popVerifier()

  test "never-completing Future triggers PendingAsyncDefect with spawn-site":
    # This file's absolute path — spawn-site diagnostic should include it.
    let thisFile = currentSourcePath()
    var raised: ref PendingAsyncDefect = nil
    # Hold `fut` in the test's scope so we can complete it AFTER the drain
    # raises. The dispatcher tracks a persistent pending-callback on every
    # `asyncCheck` until the Future is finished; leaving it uncompleted
    # across test boundaries (once this file is aggregated into
    # all_tests.nim or this suite gains a second test) will pollute
    # asyncdispatch's process-global state and make later `poll` /
    # `waitFor` calls see a stale stuck op. Completing after the raise
    # preserves the timeout signal (drain has already raised) while
    # clearing the dispatcher callback.
    var fut: Future[int]
    try:
      sandbox:
        fut = newFuture[int]("drain-timeout-probe")
        # NEVER complete/fail before drain — drainPendingAsync must time out.
        asyncCheckInSandbox(fut)
        try:
          drainPendingAsync(currentVerifier())
        except PendingAsyncDefect as e:
          raised = e
    except PendingAsyncDefect as e:
      # Covers the case where PendingAsyncDefect escapes the sandbox
      # body instead of being caught inside it.
      raised = e

    # Clear the dispatcher-tracked asyncCheck callback before test teardown
    # so this test doesn't leak a pending op to any test that runs after it.
    # Must happen after `check raised != nil` is gated — if the drain never
    # raised, the test has already failed and cleanup is moot.
    if not fut.isNil:
      fut.complete(0)
      # Drain the completion callback asyncCheck installed on the dispatcher.
      # Guarded by hasPendingOperations() because poll() raises ValueError
      # on an empty dispatcher.
      if hasPendingOperations():
        poll(timeout = 1)

    check raised != nil
    if raised != nil:
      # Lock in the full diagnostic shape so a refactor that drops the
      # "drainPendingAsync:" prefix, the "did not complete within" phrase,
      # or the per-Future line:column component would regress here.
      check thisFile in raised.msg
      check "drainPendingAsync:" in raised.msg
      check "did not complete within" in raised.msg
      check "Spawn sites:" in raised.msg
