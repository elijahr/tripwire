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

  test "multiple never-completing Futures list ALL spawn sites (Task 4.5, E7)":
    # Task 4.5 (impl plan lines 810-826, design §4.4 lines 720-729):
    # when >1 registered Future is stuck, the PendingAsyncDefect message
    # must enumerate ALL un-drained spawn sites, not just the first.
    # drainPendingAsync builds `sites: seq[string]` by iterating
    # `v.futureRegistry` and joining; this test pins that contract so a
    # refactor that breaks out after the first entry would regress here.
    #
    # RED phase note: against current impl (verify.nim lines 129-132,
    # Task 4.2 GREEN), this test passes immediately — the design already
    # enumerates all sites. Per impl plan line 822 this is therefore a
    # REGRESSION GUARD rather than a new RED→GREEN pair. The commit
    # message calls that out explicitly.
    #
    # We capture the EXACT file:line:column markers straight out of
    # `v.futureRegistry` after registration (format must match the
    # "  - filename:line:column" lines built inside drainPendingAsync),
    # so the assertion is tight to the actual origin and not a brittle
    # hand-maintained literal.
    var raised: ref PendingAsyncDefect = nil
    # Hold the Futures in the test scope so we can complete them AFTER
    # the drain raises (same rationale as the single-Future test above:
    # leaving uncompleted dispatcher callbacks pollutes process-global
    # asyncdispatch state for tests that run after this one once
    # all_tests.nim aggregation lands — Task 5.0.5).
    #
    # NOTE on variable naming: `asyncCheckInSandbox` is a template whose
    # parameter is named `fut`, and its body uses `fut:` as an object
    # constructor field for `RegisteredFuture`. Nim's hygienic template
    # substitution renames BOTH the parameter usage AND the field name
    # if the caller uses a different identifier — so `asyncCheckInSandbox(fut1)`
    # expands to `RegisteredFuture(fut1: FutureBase(fut1), ...)`, which
    # fails with "undeclared field: 'fut1'". We sidestep that by using
    # the single name `fut` inside scoped blocks (matching the parameter
    # name makes substitution a no-op on the field) and capturing each
    # Future into `futs: seq[Future[int]]` for post-drain cleanup.
    var futs: seq[Future[int]] = @[]
    var expectedSite1, expectedSite2, expectedSite3: string
    try:
      sandbox:
        let v = currentVerifier()
        block:
          let fut = newFuture[int]("drain-timeout-probe-1")
          asyncCheckInSandbox(fut)                                    # site 1
          futs.add(fut)
        block:
          let fut = newFuture[int]("drain-timeout-probe-2")
          asyncCheckInSandbox(fut)                                    # site 2
          futs.add(fut)
        block:
          let fut = newFuture[int]("drain-timeout-probe-3")
          asyncCheckInSandbox(fut)                                    # site 3
          futs.add(fut)

        # Snapshot the 3 site markers BEFORE drain clears the registry.
        # Format must mirror the "  - filename:line:column" string that
        # drainPendingAsync joins into `Spawn sites:\n...`.
        check v.futureRegistry.len == 3
        expectedSite1 = "  - " & v.futureRegistry[0].site.filename & ":" &
                        $v.futureRegistry[0].site.line & ":" &
                        $v.futureRegistry[0].site.column
        expectedSite2 = "  - " & v.futureRegistry[1].site.filename & ":" &
                        $v.futureRegistry[1].site.line & ":" &
                        $v.futureRegistry[1].site.column
        expectedSite3 = "  - " & v.futureRegistry[2].site.filename & ":" &
                        $v.futureRegistry[2].site.line & ":" &
                        $v.futureRegistry[2].site.column

        try:
          drainPendingAsync(currentVerifier())
        except PendingAsyncDefect as e:
          raised = e
    except PendingAsyncDefect as e:
      raised = e

    # Clear dispatcher-tracked asyncCheck callbacks from all 3 Futures
    # before teardown — otherwise stale pending ops leak into subsequent
    # tests when this file is aggregated into all_tests.nim (Task 5.0.5).
    # Complete-then-poll mirrors the cleanup in the single-Future test.
    for fut in futs:
      if not fut.isNil: fut.complete(0)
    if hasPendingOperations():
      poll(timeout = 1)

    check raised != nil
    if raised != nil:
      # Assert that ALL THREE spawn-site markers appear in the message.
      # The count of "  - " prefixes in the Spawn sites block must be 3,
      # and each of the captured file:line:column strings must be present.
      check expectedSite1 in raised.msg
      check expectedSite2 in raised.msg
      check expectedSite3 in raised.msg
      # Count guard: if a future refactor emits duplicate or extra site
      # lines, this pins the exact tally to 3. `count` comes from strutils.
      check raised.msg.count("  - ") == 3
      # The count prefix in the message header must report 3 futures.
      check "3 future(s) did not complete within" in raised.msg
