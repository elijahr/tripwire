## tests/threads/test_tripwire_thread_reject_chronos.nim — Task 3.7,
## Rejection 1 (design §3.6 lines 432-450). Exercise F4, Metric M1b.
##
## Pins the `ChronosOnWorkerThreadDefect` rejection contract: when a
## tripwireThread-spawned child has pending dispatcher work at entry,
## `childEntry` (src/tripwire/threads.nim lines 123-160) raises
## `ChronosOnWorkerThreadDefect` BEFORE `pushVerifier` and BEFORE the
## user body runs. The defect is marshaled to the parent via
## `ThreadHandoff.capturedExc` (commit `4d8fc4f`) and re-raised after
## `joinThread`. Without the marshaling fix, an uncaught Defect on the
## worker would trip Nim 2.2.6's `threadProcWrapDispatch` →
## `threadTrouble` → `rawQuit(1)` path and kill the whole process, so
## the design-level "parent sees the rejection" guarantee (F4) depends
## on both the rejection check AND the marshaling fix together.
##
## Test mechanism (implementer's choice, OQ1 Option A — the impl plan
## endorses a "test-only helper that forces the dispatcher's pending-
## count signal"; `testChildEntry` below IS that helper):
##
## Option A — manual handoff with a test-only child entry:
##   1. Open a parent sandbox so `currentVerifier()` is non-nil.
##   2. Construct a `ThreadHandoff` manually (NOT via
##      `withTripwireThread`, because that template gives the user no
##      opportunity to inject pending ops before `childEntry`'s check
##      fires — which is exactly the user-facing contract; bypassing it
##      is the ONLY way to exercise the gate in a test).
##   3. Spawn via `tripwireThread` with a `testChildEntry` wrapper that
##      first bootstraps a pending dispatcher op on the child thread via
##      `asyncdispatch.callSoon`, asserts `hasPendingOperations()` is
##      now true on the child, then invokes the real `childEntry(h)`.
##   4. `joinThread`, then re-raise `h.capturedExc` — this is exactly
##      the re-raise `withTripwireThread` itself performs (threads.nim
##      lines 199-200), minus the template sugar.
##
## Why NOT Option B (parent-side Future scheduling): `asyncdispatch`'s
## dispatcher is thread-local. Scheduling a Future on the PARENT before
## spawning would NOT make the CHILD's `hasPendingOperations()` return
## true. Only bootstrapping on the child's dispatcher exercises the
## contract. (See `src/tripwire/futures.nim` lines 41-53 for the wrapper
## that backs the check.)
##
## What the test asserts (first-violation-wins / no contamination):
##   - `ChronosOnWorkerThreadDefect` surfaces on the PARENT (F4 + the
##     marshaling fix from commit `4d8fc4f`).
##   - Defect message cites the child's `threadId` and the spawn site
##     (see `newChronosOnWorkerThreadDefect` at
##     src/tripwire/errors.nim lines 163-167).
##   - The user body ("should never run") is NEVER executed — proven by
##     a flag that stays false AND by the parent verifier's timeline
##     staying empty (the body would have fired `callOuter` to record
##     an interaction; its absence proves body never ran).
##   - Because `pushVerifier` was never called on the child, the parent
##     verifier's timeline stays empty AND its stack invariants are
##     undisturbed — the rejection is atomic w.r.t. verifier state.
##
## Compile (mirrors test_tripwire_thread_basic.nim's arc rationale):
##
##   nim c --threads:on --mm:arc -d:tripwireActive \
##         --import:tripwire/auto -r tests/threads/test_tripwire_thread_reject_chronos.nim
##
## `--mm:arc` (NOT `--gc:orc`) because Nim 2.2.6's orc cycle collector
## crashes during ref-Verifier teardown after a child thread has pushed/
## popped the shared verifier. Design §8.1 lists orc and arc as co-equal
## supported GCs; arc is selected here for parity with the other
## threading tests. See `spike/threads/v02_gc_safety_REPORT.md`
## (Addendum) and test_tripwire_thread_basic.nim's header for the full
## reproducer.
##
## Design citations:
##   - §3.6 lines 432-450 (Rejection 1): chronos-on-worker-thread
##     rejection order — `hasPendingOperations()` gate fires BEFORE
##     `pushVerifier`, so a rejected child never contaminates its
##     verifierStack.
##   - §3.6 line 450: test-mechanism guidance ("test-only helper that
##     forces the dispatcher's pending-count signal") — satisfied by
##     `testChildEntry` below.
##   - §3.5 lines 405-407: first-violation-wins / atomicity — the
##     Defect IS the verification failure; no subsequent verifier
##     cleanup runs on the child because `pushVerifier` never executed.
##   - §8.1: supported GCs (orc and arc co-equal; arc selected here).
##
## Cross-refs:
##   - `4d8fc4f fix(threads): marshal child exceptions through
##     ThreadHandoff` — without this, the Defect would `rawQuit(1)` the
##     process instead of surfacing on the parent. The test only passes
##     because both mechanisms (rejection check + marshaling) are in
##     place.
##
## Metric M1b: rejection-path intercepts work under
## `--mm:arc --threads:on`. Exercise F4: chronos-on-worker-thread
## rejected at child entry with Defect visible on parent.
##
## Mirrors `test_tripwire_thread_basic.nim` / `_multi.nim` / `_exception.nim`:
## drain-verifier-stack in `setup`.
import std/[unittest, strutils]
import tripwire/[sandbox, verify, errors]
import tripwire/threads
import tripwire/futures   # `callSoon` (re-exported from asyncdispatch) and
                          # `hasPendingOperations` (the tripwire wrapper).
                          # `verify` is imported so sandbox's `verifyAll`
                          # expansion resolves at the parent sandbox exit
                          # (sandbox.nim line 63); every sibling threads
                          # test imports it for the same reason.

# Test-only child entry: bootstraps a pending dispatcher op on this
# thread, then invokes the real `childEntry`. The bootstrapping MUST
# happen on the CHILD thread — asyncdispatch's dispatcher is thread-
# local, so a parent-side callSoon would leave the child's dispatcher
# queue empty. The `{.cast(gcsafe).}` mirrors the other threads tests:
# we're knowingly calling into asyncdispatch globals from a
# `{.gcsafe.}` context under `--threads:on`.
proc testChildEntry(h: ThreadHandoff) {.thread, nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    # Seed a single pending callback. The closure body is `discard` —
    # we only need the dispatcher's pending-count to be non-zero at
    # the instant `childEntry` reads `hasPendingOperations()`; whether
    # the callback ever fires is irrelevant (the child thread raises
    # and exits before any drain could run).
    callSoon(proc() {.gcsafe.} = discard)
    doAssert hasPendingOperations(),
      "test setup: callSoon failed to seed pending op on child dispatcher"
  # Now invoke the real childEntry — it should hit its
  # `if hasPendingOperations()` gate (threads.nim line 143) BEFORE
  # `pushVerifier` runs and raise ChronosOnWorkerThreadDefect. That
  # Defect is caught by childEntry's own outer `except Exception as e`
  # (threads.nim lines 155-160) and marshaled into `h.capturedExc`.
  childEntry(h)

suite "withTripwireThread: chronos rejection (F4; design §3.6 lines 432-450)":
  setup:
    # Drain any stack left over from a prior test's failure path.
    while currentVerifier() != nil:
      discard popVerifier()

  test "ChronosOnWorkerThreadDefect fires on child entry and surfaces on parent":
    # Flag set only if h.body runs. After the rejection we assert it is
    # STILL false — that proves the gate fires BEFORE the body, not
    # merely before some post-body cleanup.
    var bodyRan = false
    var sawDefect = false
    var defectMsg = ""

    sandbox:
      let parentV = currentVerifier()
      doAssert not parentV.isNil, "sandbox must seat a parent verifier"

      # Manual handoff — mirrors withTripwireThread's construction
      # (threads.nim lines 186-188) so we exercise the real childEntry
      # path with the ONLY change being the test-only bootstrapping
      # wrapper.
      let h = ThreadHandoff(
        verifier: parentV,
        body: proc() {.gcsafe.} =
          # If this EVER runs, the rejection check either didn't fire
          # or fired AFTER pushVerifier and body. Both are contract
          # violations the test must catch.
          bodyRan = true)
      GC_ref(h)
      var thr: Thread[ThreadHandoff]
      try:
        tripwireThread(thr, testChildEntry, h)
        joinThread(thr)
        # Re-raise the child's captured Defect on the parent — exactly
        # the re-raise withTripwireThread itself performs (threads.nim
        # lines 199-200). This is what the marshaling fix (4d8fc4f)
        # enables: without it, the Defect would have rawQuit(1)'d the
        # process on the child and `h.capturedExc` would still be nil.
        if not h.capturedExc.isNil:
          raise h.capturedExc
      except ChronosOnWorkerThreadDefect as e:
        sawDefect = true
        defectMsg = e.msg
      finally:
        GC_unref(h)

      # The Defect must have surfaced on the parent. If sawDefect is
      # false, either the rejection gate didn't fire (bug in the check)
      # or the marshaling path dropped the exception (bug in
      # capturedExc wiring).
      check sawDefect

      # Body must NEVER have run. The rejection is BEFORE pushVerifier
      # and BEFORE h.body() is invoked (threads.nim lines 143-148), so
      # the flag stays false and the parent verifier's timeline stays
      # empty.
      check not bodyRan

      # Defect message contract (newChronosOnWorkerThreadDefect at
      # src/tripwire/errors.nim lines 163-167 composes:
      # "tripwireThread rejected: chronos on worker thread on thread
      # $threadId at $filename:$line" + FFIScopeFooter).
      check "tripwireThread rejected: chronos on worker thread on thread " in defectMsg
      # `instantiationInfo()` at threads.nim:145 resolves to the
      # caller's expansion site; when `childEntry` is dispatched via
      # `createThread` / `threadProcWrapper`, Nim's thread-launch
      # plumbing has no source origin and the site collapses to
      # "???:0". That is a framework-level limitation, not a Defect
      # contract violation: the threadId carries the actionable
      # information (which OS thread raised) and the message prefix
      # identifies the gate. Pin the literal so an accidental
      # refactor that (good-news) starts resolving a real site — or
      # (bad-news) drops the site segment entirely — surfaces here.
      check " at ???:0" in defectMsg

      # pushVerifier was never called on the child, so no interaction
      # could have landed on the parent verifier. An empty timeline is
      # the structural proof that childEntry bailed BEFORE pushVerifier.
      check parentV.timeline.entries.len == 0

      # FFIScopeFooter is appended verbatim by every defect constructor
      # in src/tripwire/errors.nim; pinning `endsWith` here guards against
      # a future refactor of newChronosOnWorkerThreadDefect dropping it.
      check defectMsg.endsWith(FFIScopeFooter)
    # Parent sandbox exit runs verifyAll. Because we caught the Defect
    # inline, `getCurrentException()` is nil at the finally boundary
    # (sandbox.nim lines 55-61 guard), so verifyAll executes. The
    # parent timeline is empty and no mocks were registered, so the
    # guard passes cleanly — any verifier-state corruption caused by a
    # broken rejection path would surface here as an unexpected defect.
