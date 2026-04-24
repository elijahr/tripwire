## tests/threads/test_tripwire_thread_reject_nested.nim — Task 3.8,
## Rejection 2 (design §3.6 lines 452-463). Exercise E4, Metric M1b.
##
## Pins the `NestedTripwireThreadDefect` rejection contract: when the
## current thread's `verifierStack` is already non-empty at the entry
## of `runWithVerifier` or `childEntry`, the nested-invocation gate
## (`src/tripwire/threads.nim` lines 110-112 and 138-140 respectively)
## raises `NestedTripwireThreadDefect` BEFORE any new verifier is
## pushed and BEFORE the user body runs. For the `childEntry` path the
## defect is marshaled to the parent via `ThreadHandoff.capturedExc`
## (commit `4d8fc4f`) and re-raised after `joinThread`.
##
## Honest design-vs-implementation gap (do not paper over):
##
## The impl-plan one-liner for Task 3.8 reads "`withTripwireThread`
## inside another `withTripwireThread` raises `NestedTripwireThreadDefect`".
## That phrasing over-claims relative to what the v0.2 check actually
## catches. `verifierStack` is a `{.threadvar.}` (`src/tripwire/sandbox.nim`
## line 23), so each OS thread gets an independently zero-initialised
## stack. A naive nested scenario — parent thread opens a sandbox,
## spawns child A via `withTripwireThread`, and inside A's body A
## itself calls `withTripwireThread` to spawn grandchild B — does NOT
## trip `childEntry`'s `verifierStack.len > 0` guard on B, because B
## is a fresh OS thread whose stack is empty by language semantics.
## In that shape the grandchild silently inherits A's captured verifier
## reference and runs to completion; the v0.2 design explicitly calls
## that scenario out as Exercise E8 (§3.7.1), NOT as an E4 rejection.
## Task 3.9 is the home for grandchild-spawn coverage.
##
## What the v0.2 nested-tripwireThread gate DOES catch (E4, §3.6
## lines 452-463):
##
##   (a) `runWithVerifier(v, body)` invoked on a thread whose
##       `verifierStack` is already non-empty. Two user-facing shapes:
##       (a1) from inside a `sandbox:` block on the parent thread (the
##            sandbox has already pushed a verifier); and
##       (a2) from inside the body of a `withTripwireThread` block
##            (child thread — `childEntry` has pushed the parent
##            verifier on the child's stack before invoking the body).
##       Both shapes hit the `verifierStack.len > 0` check at
##       threads.nim line 110.
##
##   (b) Direct / defensive invocation of `childEntry(h)` on a thread
##       whose stack was pre-seeded by manual `pushVerifier(...)`.
##       This is a misuse-path guard; real users never call
##       `childEntry` directly (it is marked INTERNAL at
##       threads.nim line 124). We exercise it the same way Task 3.7
##       exercises the chronos gate — a manual handoff with a
##       test-only `testChildEntry` wrapper that pre-seeds the stack
##       before delegating to the real `childEntry`.
##
## Test design — two complementary shapes pin the contract from both
## sides:
##
##   Test 1 (shape a2) — `runWithVerifier` inside
##   `withTripwireThread` body: the user-facing, natural scenario.
##   `childEntry` pushes the parent verifier onto the child's stack;
##   user body then calls `runWithVerifier(innerV, ...)`, which sees
##   `verifierStack.len > 0` on the child and raises
##   `NestedTripwireThreadDefect`. The defect is caught by
##   `childEntry`'s outer `except Exception as e` (threads.nim lines
##   155-160) and marshaled into `h.capturedExc`. The parent's
##   `withTripwireThread` re-raises after `joinThread` (threads.nim
##   lines 199-200). This is the E4 contract for the runWithVerifier
##   gate.
##
##   Test 2 (shape b) — manual `childEntry` invocation on a pre-seeded
##   stack: mirrors Task 3.7's Option A. A test-only
##   `testNestedChildEntry` wrapper pre-seeds the child's stack via
##   `pushVerifier(newVerifier("seed"))` and then invokes the real
##   `childEntry(h)`, which hits its own first-rejection check at
##   threads.nim lines 138-140 and raises `NestedTripwireThreadDefect`.
##   Same marshaling + re-raise path as Test 1. The seed verifier is
##   a throwaway local — it pollutes no real parent state.
##
## What each test asserts:
##   - `NestedTripwireThreadDefect` surfaces on the PARENT (E4 + the
##     marshaling fix from commit `4d8fc4f`).
##   - Defect message matches the exact prefix composed by
##     `newNestedTripwireThreadDefect` at `src/tripwire/errors.nim`
##     lines 169-173 ("tripwireThread rejected: nested tripwire thread
##     on thread $threadId at $filename:$line") and ends with
##     `FFIScopeFooter` (appended verbatim by every defect constructor
##     in that file).
##   - The user body ("should never run") is NEVER executed — proven
##     by the `bodyRan` flag staying false, the authoritative
##     ordering-check that the rejection fired BEFORE any body was
##     invoked. For Test 2 the body is the no-op `doAssert false`
##     closure on the handoff; for Test 1 the body is the
##     `runWithVerifier` inner body.
##   - Parent verifier timeline is empty — a consistency check that
##     no interaction leaked from the rejection path. Same caveat as
##     Task 3.7: not a discriminator for pushVerifier ordering (no
##     TRM fires here), but a guard against a future refactor that
##     records against the parent from inside the rejection path.
##
## On `instantiationInfo()` resolution (Task 3.7 discovery): when
## `childEntry` is dispatched via `createThread` / `threadProcWrapper`,
## Nim's thread-launch plumbing has no source origin for the raise
## site and `instantiationInfo()` at threads.nim:145 (chronos) and
## threads.nim:139 (nested) collapses to `???:0`. That same collapse
## applies to Test 2 here. For Test 1 the raise site is
## `runWithVerifier`'s template expansion INSIDE the user body on the
## child; `instantiationInfo()` at threads.nim:111 MAY resolve to a
## real location (the call-site of `runWithVerifier`) or may also
## collapse depending on how Nim threads template expansion sites
## through `threadProcWrapper`. We pin the observed literal in each
## test rather than claim a framework-general answer.
##
## Compile (mirrors test_tripwire_thread_basic.nim's arc rationale):
##
##   nim c --threads:on --mm:arc -d:tripwireActive \
##         --import:tripwire/auto -r tests/threads/test_tripwire_thread_reject_nested.nim
##
## `--mm:arc` (NOT `--gc:orc`) because Nim 2.2.6's orc cycle collector
## crashes during ref-Verifier teardown after a child thread has
## pushed/popped the shared verifier. Design §8.1 lists orc and arc
## as co-equal supported GCs; arc is selected here for parity with
## the sibling threads tests. See `spike/threads/v02_gc_safety_REPORT.md`
## (Addendum) and `test_tripwire_thread_basic.nim` header for the
## full reproducer.
##
## Design citations:
##   - §3.6 lines 452-463 (Rejection 2): nested-tripwireThread
##     rejection — `verifierStack.len > 0` gates fire BEFORE
##     pushVerifier and BEFORE the body, so a rejected invocation
##     never contaminates the stack.
##   - §3.7.1 (E8): grandchild-spawn semantics — explicitly out of
##     scope for Task 3.8; the v0.2 gate does NOT catch this shape
##     (per the "design-vs-implementation gap" note above). Task 3.9
##     covers grandchild spawning.
##   - §3.5 lines 405-407: first-violation-wins / atomicity — the
##     Defect IS the verification failure; no subsequent verifier
##     cleanup runs on the rejected invocation because pushVerifier
##     never executed.
##   - §8.1: supported GCs (orc and arc co-equal; arc selected here).
##
## Cross-refs:
##   - `4d8fc4f fix(threads): marshal child exceptions through
##     ThreadHandoff` — without this, the Defect raised on the child
##     would `rawQuit(1)` the process instead of surfacing on the
##     parent. Both tests only pass because rejection check AND
##     marshaling are in place.
##
## Metric M1b: rejection-path intercepts work under
## `--mm:arc --threads:on`. Exercise E4: nested tripwireThread
## rejected with Defect visible on parent.
##
## Mirrors `test_tripwire_thread_reject_chronos.nim`: manual handoff,
## test-only child-entry wrapper, drain-verifier-stack in `setup`.
import std/[unittest, strutils]
import tripwire/[sandbox, verify, errors]
import tripwire/threads

# Test-only child entry for Test 2: pre-seeds the current thread's
# verifierStack with a throwaway verifier, then invokes the real
# `childEntry`. The seeding MUST happen on the CHILD thread —
# `verifierStack` is a `{.threadvar.}` (sandbox.nim line 23), so a
# parent-side push would leave the child's stack empty. The `seed`
# verifier is a local newVerifier so the gate fires naturally on
# `verifierStack.len > 0` without borrowing any sandbox-owned state.
# We deliberately do NOT pop the seed before invoking `childEntry`:
# the entire point is to force the stack-non-empty gate to fire at
# the first rejection check (threads.nim lines 138-140). `{.cast(gcsafe).}`
# mirrors the sibling threads tests' pattern for knowingly calling
# `newVerifier`/`pushVerifier` from a `{.gcsafe.}` thread proc.
proc testNestedChildEntry(h: ThreadHandoff) {.thread, nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    discard pushVerifier(newVerifier("seed"))
  childEntry(h)

suite "withTripwireThread: nested rejection (E4; design §3.6 lines 452-463)":
  setup:
    # Drain any stack left over from a prior test's failure path.
    while currentVerifier() != nil:
      discard popVerifier()

  test "runWithVerifier inside withTripwireThread body is rejected":
    # Shape (a2) from the header: the `withTripwireThread` child has
    # parent verifier pushed on its stack; body then invokes
    # `runWithVerifier`, whose gate (threads.nim line 110) raises
    # NestedTripwireThreadDefect. Defect marshals to parent via
    # `ThreadHandoff.capturedExc` and re-raises after joinThread.
    var bodyRan = false
    var sawDefect = false
    var defectMsg = ""

    sandbox:
      let parentV = currentVerifier()
      doAssert not parentV.isNil, "sandbox must seat a parent verifier"

      try:
        withTripwireThread:
          # Inside child A: A's stack = [parentV] (pushed by
          # childEntry). Now invoke `runWithVerifier` — its
          # nested-check (threads.nim line 110) fires because
          # verifierStack.len is 1, not 0.
          runWithVerifier(newVerifier("inner")):
            # If this EVER runs, the gate either didn't fire or
            # fired AFTER pushing the inner verifier and entering
            # the body. Both are contract violations the test
            # must catch.
            bodyRan = true
      except NestedTripwireThreadDefect as e:
        sawDefect = true
        defectMsg = e.msg

      # Defect must have surfaced on the parent. If false, either
      # the rejection gate didn't fire (bug in the check) or the
      # marshaling path dropped the exception (bug in capturedExc
      # wiring — commit 4d8fc4f).
      check sawDefect

      # Body must NEVER have run. The gate is BEFORE pushVerifier
      # and BEFORE the body (threads.nim lines 110-115), so the
      # flag stays false.
      check not bodyRan

      # Defect message prefix contract (newNestedTripwireThreadDefect
      # at src/tripwire/errors.nim lines 169-173 composes:
      # "tripwireThread rejected: nested tripwire thread on thread
      # $threadId at $filename:$line" + FFIScopeFooter).
      check "tripwireThread rejected: nested tripwire thread on thread " in defectMsg

      # FFIScopeFooter is appended verbatim by every defect
      # constructor; pinning endsWith guards against a future
      # refactor of newNestedTripwireThreadDefect dropping it.
      check defectMsg.endsWith(FFIScopeFooter)

      # Consistency check: no interaction leaked to the parent
      # timeline. The body fires no TRM, so this does NOT
      # discriminate pushVerifier-ran-vs-didn't; the authoritative
      # ordering proof is `check not bodyRan` above. Still worth
      # pinning as a guard against a future refactor that records
      # against the parent from inside the rejection path.
      check parentV.timeline.entries.len == 0
    # Parent sandbox exit runs verifyAll. Because we caught the
    # Defect inline, `getCurrentException()` is nil at the finally
    # boundary (sandbox.nim lines 55-61 guard), so verifyAll
    # executes against an empty parent timeline and zero-mock queue
    # and passes cleanly.

  test "childEntry with pre-seeded stack raises NestedTripwireThreadDefect":
    # Shape (b) from the header: manual handoff with a test-only
    # wrapper that pre-seeds the child's verifierStack, exercising
    # the defensive gate at threads.nim lines 138-140. Real users
    # never call `childEntry` directly (it's INTERNAL per
    # threads.nim line 124); the gate is a misuse guard.
    var bodyRan = false
    var sawDefect = false
    var defectMsg = ""

    sandbox:
      let parentV = currentVerifier()
      doAssert not parentV.isNil, "sandbox must seat a parent verifier"

      # Manual handoff — mirrors `withTripwireThread`'s construction
      # (threads.nim lines 186-188) so we exercise the real
      # `childEntry` path with the ONLY change being the test-only
      # stack-seeding wrapper.
      let h = ThreadHandoff(
        verifier: parentV,
        body: proc() {.gcsafe.} =
          # If this EVER runs, the rejection check either didn't
          # fire or fired AFTER pushVerifier and body. Both are
          # contract violations the test must catch.
          bodyRan = true)
      GC_ref(h)
      var thr: Thread[ThreadHandoff]
      try:
        tripwireThread(thr, testNestedChildEntry, h)
        joinThread(thr)
        # Re-raise the child's captured Defect on the parent —
        # exactly the re-raise `withTripwireThread` itself
        # performs (threads.nim lines 199-200). This is what the
        # marshaling fix (4d8fc4f) enables: without it, the
        # Defect would have rawQuit(1)'d the process on the child
        # and `h.capturedExc` would still be nil.
        if not h.capturedExc.isNil:
          raise h.capturedExc
      except NestedTripwireThreadDefect as e:
        sawDefect = true
        defectMsg = e.msg
      finally:
        GC_unref(h)

      # Defect must have surfaced on the parent.
      check sawDefect

      # Body must NEVER have run. The gate is BEFORE pushVerifier
      # and BEFORE h.body() (threads.nim lines 138-148), so the
      # flag stays false.
      check not bodyRan

      # Defect message prefix contract (same constructor as
      # Test 1).
      check "tripwireThread rejected: nested tripwire thread on thread " in defectMsg

      # `instantiationInfo()` at threads.nim:139 collapses to
      # `???:0` when `childEntry` is dispatched via
      # `createThread` / `threadProcWrapper` (Task 3.7 discovery;
      # same Nim-framework limitation, same collapse). Pin the
      # literal so an accidental refactor that (good-news) starts
      # resolving a real site — or (bad-news) drops the site
      # segment entirely — surfaces here.
      check " at ???:0" in defectMsg

      # FFIScopeFooter pinning (same rationale as Test 1).
      check defectMsg.endsWith(FFIScopeFooter)

      # Consistency check: no interaction leaked to the parent
      # timeline (same rationale as Test 1).
      check parentV.timeline.entries.len == 0
    # Parent sandbox exit: verifyAll runs on parent verifier,
    # sees zero unasserted interactions and zero unused mocks,
    # passes cleanly.
