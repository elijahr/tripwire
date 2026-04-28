## tripwire/verify.nim — mock registration, popMatchingMock, verifyAll,
## fingerprint helpers, drainPendingAsync (design §4.4).
##
## `./futures` is imported (rather than `std/asyncdispatch` directly) to
## preserve the chronos-aware `hasPendingOperations` wrapper defined there
## (design §9, §10). `futures` re-exports `std/asyncdispatch except
## hasPendingOperations`, so `poll` is also available via the same import.
## No circular import: `futures.nim` does not import `verify.nim`.
import std/[tables, deques, options, monotimes, times, strutils]
import ./[types, timeline, sandbox, errors, async_registry_types, futures]

proc registerMock*(v: Verifier, pluginName: string, m: Mock) =
  if pluginName notin v.mockQueues:
    v.mockQueues[pluginName] = MockQueue(mocks: initDeque[Mock]())
  v.mockQueues[pluginName].mocks.addLast(m)

proc popMatchingMock*(v: Verifier, pluginName, procName,
                     fingerprint: string): Option[Mock] {.raises: [].} =
  ## Hot-path TRM helper. Annotated `{.raises: [].}` so `tripwireInterceptBody`
  ## / `tripwirePluginIntercept` can sit inside chronos `async: (raises: [...])`
  ## procs without leaking `KeyError`. Uses `withValue` to avoid raising on
  ## table key absence (the `notin`-then-`[]` pattern that Nim's effect
  ## inference can't prove safe).
  ##
  ## Defensive nil-guard: this proc is exported and embedded in TRM
  ## expansions that may evaluate before any sandbox is open (e.g.,
  ## an instrumented call that fires from module-init code, or a
  ## test that exercises the pop path directly). Without the guard,
  ## `v.mockQueues.withValue` SIGSEGVs.
  result = none(Mock)
  if v.isNil: return
  v.mockQueues.withValue(pluginName, qPtr):
    # Take mutable pointer via withValue; field assignment persists
    # because MockQueue carries a Deque[Mock] (ref-backed).
    if qPtr[].mocks.len == 0: return
    let head = qPtr[].mocks[0]
    if head.procName == procName and head.argFingerprint == fingerprint:
      return some(qPtr[].mocks.popFirst())
    if v.context.inAnyOrderActive:
      for i in 0 ..< qPtr[].mocks.len:
        if qPtr[].mocks[i].procName == procName and
           qPtr[].mocks[i].argFingerprint == fingerprint:
          # Capture BEFORE mutating the deque (§4.1 regression guard).
          let matched = qPtr[].mocks[i]
          var tmp: seq[Mock]
          for j in 0 ..< qPtr[].mocks.len:
            if j != i: tmp.add(qPtr[].mocks[j])
          qPtr[].mocks.clear()
          for mm in tmp: qPtr[].mocks.addLast(mm)
          return some(matched)

proc verifyAll*(v: Verifier) =
  ## Check the three guarantees. Raises the FIRST violation.
  # Guarantee 2: every recorded interaction explicitly asserted.
  var unasserted: seq[Interaction] = @[]
  for i in v.timeline.unasserted: unasserted.add(i)
  if unasserted.len > 0:
    raise newUnassertedInteractionsDefect(v.name, unasserted)
  # Guarantee 3: every registered mock consumed.
  var unusedMocks: seq[Mock] = @[]
  for pluginName, q in v.mockQueues.pairs:
    for m in q.mocks: unusedMocks.add(m)
  if unusedMocks.len > 0:
    raise newUnusedMocksDefect(v.name, unusedMocks)
  # Guarantee 1 is raised eagerly by TRM bodies; nothing to do here.

proc fingerprintOf*(procName: string, renderedArgs: seq[string]): string =
  ## Deterministic canonicalization. Format: procName|arg0|arg1|...
  result = procName
  for a in renderedArgs:
    result.add('|')
    result.add(a)

const tripwireAsyncDrainTimeoutMs* {.intdefine: "tripwireAsyncDrainTimeoutMs".}: int = 5000
  ## Default drain timeout per verifier. Configurable at compile time via
  ## `-d:tripwireAsyncDrainTimeoutMs:N`.

proc drainPendingAsync*(v: Verifier) =
  ## Drive the asyncdispatch dispatcher until every Future in
  ## `v.futureRegistry` has completed or `tripwireAsyncDrainTimeoutMs`
  ## has elapsed. Blocks on the current thread.
  ##
  ## STAYS SYNC. Uses `std/asyncdispatch.poll` with short internal
  ## intervals (50ms default) to honor the cap.
  ##
  ## ASYNCDISPATCH-ONLY. Chronos Futures cannot be registered via
  ## `asyncCheckInSandbox` in v0.2 (compile-time {.warning.}, §4.1);
  ## therefore `v.futureRegistry` only holds asyncdispatch Futures,
  ## which `std/asyncdispatch.poll` can drive. See §11 non-goals.
  ##
  ## Raises:
  ##   - `PendingAsyncDefect` with per-Future spawn-site origin if timeout
  ##     elapses before the registry drains. The defect message lists
  ##     every remaining `RegisteredFuture.site` so the user can trace
  ##     which spawn never completed.
  ##   - any exception raised by a completing Future's failure handler,
  ##     re-raised with the Future's spawn-site attached to the diagnostic.
  if v.futureRegistry.len == 0:
    return

  let deadline = getMonoTime() + initDuration(
    milliseconds = tripwireAsyncDrainTimeoutMs)

  while getMonoTime() < deadline:
    # Remove completed entries in-place; continue until all complete
    # or we hit the deadline. Failed Futures raise on inspection; we
    # wrap-and-rethrow with the spawn-site attached so the diagnostic
    # points at the user's asyncCheckInSandbox call rather than at the
    # drain loop.
    var i = 0
    while i < v.futureRegistry.len:
      if v.futureRegistry[i].fut.finished:
        if v.futureRegistry[i].fut.failed:
          let entry = v.futureRegistry[i]
          # Deviation from design §4.4 line 705: `readError` is generic
          # over `Future[T]`, not available on `FutureBase`. `FutureBase`
          # exposes the stored exception via the public `error*` field
          # (see stdlib asyncfutures.nim line 30). Semantics match.
          raise newPendingAsyncDefect(
            "registered Future failed (spawned at " &
            entry.site.filename & ":" & $entry.site.line & ":" &
            $entry.site.column & ")",
            parent = entry.fut.error)
        v.futureRegistry.del(i)   # del is O(1) swap-remove; order doesn't matter for drain
      else:
        inc i
    if v.futureRegistry.len == 0:
      return

    # Block-on-progress for a bounded slice, capped by remaining
    # budget so the whole drain cannot overshoot
    # tripwireAsyncDrainTimeoutMs by more than one poll iteration.
    if hasPendingOperations():
      let remainingMs = (deadline - getMonoTime()).inMilliseconds.int
      if remainingMs <= 0:
        break
      poll(timeout = min(50, remainingMs))   # asyncdispatch.poll only; chronos is rejected upstream
    else:
      # Registry non-empty but dispatcher has nothing to progress ==
      # a never-completing Future. Bail with diagnostic.
      break

  # Timeout or stuck. Raise with per-Future spawn-site diagnostics.
  var sites: seq[string] = @[]
  for entry in v.futureRegistry:
    sites.add("  - " & entry.site.filename & ":" & $entry.site.line &
              ":" & $entry.site.column)
  raise newPendingAsyncDefect(
    "drainPendingAsync: " & $v.futureRegistry.len &
    " future(s) did not complete within " &
    $tripwireAsyncDrainTimeoutMs & "ms. Spawn sites:\n" &
    sites.join("\n"),
    parent = nil)
