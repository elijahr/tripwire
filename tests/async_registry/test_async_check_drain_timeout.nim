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
    try:
      sandbox:
        let fut = newFuture[int]("drain-timeout-probe")
        # NEVER complete/fail — drainPendingAsync must time out.
        asyncCheckInSandbox(fut)
        try:
          drainPendingAsync(currentVerifier())
        except PendingAsyncDefect as e:
          raised = e
          # Drain the dispatcher-tracked asyncCheck so sandbox's
          # implicit verifyAll doesn't see a stale queued callback.
          # (asyncdispatch.poll is a no-op if nothing is pending.)
          discard
    except PendingAsyncDefect as e:
      # Covers the case where PendingAsyncDefect escapes the sandbox
      # body instead of being caught inside it.
      raised = e

    check raised != nil
    if raised != nil:
      check thisFile in raised.msg
