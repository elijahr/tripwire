## tests/threads/test_tripwire_thread_nested_sandbox_spawn.nim — Task 3.9,
## Exercise E8 (design §3.7.1): GRANDCHILD-spawn scenario.
##
## Pins the DOCUMENTED behavior: when a child thread's body opens an inner
## `sandbox:` block AND THEN spawns a grandchild via `withTripwireThread`
## from INSIDE that inner sandbox, the grandchild inherits the INNER
## verifier (NOT the outermost parent's). This is because
## `withTripwireThread` captures `currentVerifier()` at spawn time, and
## at that moment the top of the child's thread-local verifier stack is
## the inner sandbox's freshly-pushed verifier — not the outermost
## parent's verifier that the child borrowed on entry.
##
## Why this matters (E8 row, design §3.7.1): composing tests that nest
## `sandbox` inside `withTripwireThread` bodies AND spawn grandchildren
## from those nested sandboxes surface a subtle scoping rule: the
## grandchild's TRM interactions land on the INNER verifier's timeline,
## not the outer parent's. This is NOT a bug — it is the straightforward
## consequence of `withTripwireThread` using `currentVerifier()` — but it
## IS a hazard to call out in docs. Users expecting "the grandchild sees
## my outer expectations" will be surprised; users treating the inner
## sandbox as a genuine isolation boundary will get exactly what they
## asked for.
##
## The verifier-stack invariant being pinned:
##   - Parent opens outer `sandbox:` → parent stack: [parentV] (len 1).
##     `currentVerifier()` on the parent thread is parentV.
##   - Parent calls `withTripwireThread: childBody`. Child A thread
##     spawns; childEntry pushes parentV onto A's thread-local stack.
##     A's stack: [parentV] (len 1).
##   - Inside A's body, A opens an inner `sandbox("inner"):` block.
##     sandbox's pushVerifier adds a fresh innerV. A's stack:
##     [parentV, innerV] (len 2). `currentVerifier()` on A is innerV.
##   - Inside A's inner sandbox, A calls `withTripwireThread: grandBody`.
##     `withTripwireThread` captures `currentVerifier()` — innerV —
##     into the ThreadHandoff.verifier field. Grandchild B spawns;
##     B's childEntry pushes innerV onto B's thread-local stack.
##     B's stack: [innerV] (len 1). `currentVerifier()` on B is innerV.
##   - B's body fires a TRM. The interaction lands on innerV.timeline —
##     NOT parentV.timeline.
##   - B joins back on A (still inside A's inner sandbox). B's stack:
##     empty again (raw pop after body).
##   - A consumes the grandchild's interaction via
##     `innerV.timeline.markAsserted` so that the inner sandbox's exit
##     verifyAll sees a clean innerV timeline.
##   - A's inner sandbox exits: popVerifier retires innerV, verifyAll
##     runs on innerV cleanly. A's stack back to [parentV] (len 1).
##   - A's body returns. childEntry does raw `verifierStack.pop()`
##     removing parentV (borrowed, so NOT retired). A's stack empty.
##   - Parent's post-join assertions verify that parentV.timeline.entries.len
##     == 0 (the grandchild's interaction did NOT leak to parent) and
##     that the inner sandbox's verifyAll was happy.
##
## Contrast with E6 (`test_tripwire_thread_nested_sandbox.nim`):
##   E6: child fires TRM INSIDE inner sandbox → inner verifier catches it.
##   E8: GRANDCHILD (spawned from inside inner sandbox) fires TRM →
##   inner verifier catches it, NOT outer parent. The grandchild's
##   spawn-time `currentVerifier()` is innerV, so innerV is what gets
##   inherited, not parentV.
##
## Compile (mirrors test_tripwire_thread_nested_sandbox.nim's arc rationale):
##
##   nim c --threads:on --mm:arc -d:tripwireActive \
##         --import:tripwire/auto -r tests/threads/test_tripwire_thread_nested_sandbox_spawn.nim
##
## `--mm:arc` (NOT `--gc:orc`) because Nim 2.2.6's orc cycle collector
## crashes during ref-Verifier teardown after a child thread has pushed/
## popped the shared verifier. See `spike/threads/v02_gc_safety_REPORT.md`
## (Addendum). Design §8.1 lists orc and arc as co-equal supported GCs.
##
## Design citations:
##   - §3.7.1 (E8 row): grandchild-spawn semantics — grandchild inherits
##     innermost sandbox verifier at spawn time because that is what
##     `currentVerifier()` returns at spawn time. Documented behavior,
##     not a bug.
##   - §3.3: handoff mechanism — whatever verifier `currentVerifier()`
##     returns at spawn site is the verifier the new child will push.
##   - §3.5 (lines 409-427): multi-level handoff discipline — the
##     thread-local stack rules that make E6 safe apply recursively
##     to E8.
##   - §8.1: supported GCs (arc selected here).
##
## Metric: M1 (threading intercepts work under `--mm:arc --threads:on`).
## Not a new metric — part of M1's broader threading-correctness story.
##
## Mirrors `test_tripwire_thread_nested_sandbox.nim` structure: module-scope
## `mockable`, `{.gcsafe.}`-cast wrappers, drain-verifier-stack in `setup`.
import std/[unittest, options, tables]
import tripwire/[types, timeline, sandbox, verify]
import tripwire/plugins/mock
import tripwire/threads

# Two distinct user procs:
#   - `outerCall` is mocked on the PARENT verifier. It is NEVER fired
#     in this test — it is only registered on the parent so that if the
#     grandchild's interaction erroneously leaked onto parentV instead
#     of innerV, parentV's verifyAll would NOT catch it via
#     UnusedMocksDefect (the parent expectation would be consumed by the
#     leaked grandchild interaction if the mocked procs had matching
#     fingerprints). We DO fire outerCall on the parent thread itself
#     BEFORE spawning, so the parent expectation's lifecycle is
#     complete-and-consumed before the child spawns; this keeps the
#     "parent must not have child's interaction" assertion clean.
#   - `grandCall` is mocked on the INNER verifier (inside A's inner
#     sandbox, before A spawns B). B's body fires grandCall. The
#     interaction lands on innerV.timeline, consumed by A inside the
#     inner sandbox before inner-sandbox exit.
proc outerCall(x: int): int =
  x * 10   # real impl; TRM intercepts
proc grandCall(y: int): int =
  y * 100  # real impl; TRM intercepts

# Module-scope TRM emissions. Dummy args only provide arity/types.
mockable(outerCall(0))
mockable(grandCall(0))

# Wrapper procs — mirror the nested-sandbox/multi/exception tests'
# {.gcsafe.}-cast pattern. The cast is safe because `mockPluginInstance`
# is an immutable module-scope let and verifier state is shared via ref;
# see basic-test header for the full rationale.
proc callOuter(x: int): int {.gcsafe.} =
  {.cast(gcsafe).}:
    outerCall(x)

proc callGrand(y: int): int {.gcsafe.} =
  {.cast(gcsafe).}:
    grandCall(y)

suite "withTripwireThread: grandchild-spawn from inner sandbox (E8)":
  setup:
    # Drain any stack left over from a prior test's failure path.
    while currentVerifier() != nil:
      discard popVerifier()

  test "grandchild inherits inner sandbox verifier (NOT outer parent)":
    # Grandchild body fires grandCall. Its interaction must land on
    # innerV.timeline (the inner sandbox's verifier, which is what
    # currentVerifier() returns at the spawn site inside A's inner
    # sandbox). It must NOT land on parentV.timeline.
    proc grandBody() {.gcsafe.} =
      # Sentinel 9700 distinct from real-impl result 7*100=700 — a TRM
      # fall-through would return 700 and hide the miss.
      doAssert callGrand(7) == 9700

    # Child A body: opens an inner sandbox, registers grandCall's mock
    # on the inner verifier, spawns grandchild B from INSIDE the inner
    # sandbox, joins B, then consumes B's interaction on the inner
    # verifier before the inner sandbox's exit verifyAll runs.
    proc childBody() {.gcsafe.} =
      # Child A's verifierStack at entry: [parentV] (len 1).
      doAssert verifierStack.len == 1

      # Open an inner sandbox on child A. sandbox pushes a fresh verifier.
      # A's stack: [parentV, innerV] (len 2). Inner verifier is the top;
      # currentVerifier() == innerV.
      sandbox:
        doAssert verifierStack.len == 2
        let innerV = currentVerifier()
        doAssert not innerV.isNil

        # Register grandCall's mock on the INNER verifier. B will fire
        # grandCall; since B inherits innerV (see §3.7.1 E8), the TRM
        # fires against innerV and consumes this expectation.
        # Sentinel 9700 — real impl produces 7*100=700, so this value
        # cannot come from a fall-through.
        mock.expect grandCall(7):
          respond value: 9700

        # Spawn grandchild B from INSIDE the inner sandbox. At this
        # spawn site, `currentVerifier()` returns innerV (top of A's
        # stack). `withTripwireThread` captures innerV into the
        # ThreadHandoff.verifier field. B's childEntry pushes innerV
        # onto B's thread-local stack. B's TRM therefore resolves
        # against innerV — NOT parentV.
        withTripwireThread:
          grandBody()

        # B has joined. B's interaction must be on innerV.timeline.
        # Consume it so inner-sandbox exit verifyAll sees a clean
        # timeline. If E8 semantics had regressed (grandchild inheriting
        # parentV instead of innerV), innerV.timeline.entries.len would
        # be 0 here and this doAssert would fire.
        doAssert innerV.timeline.entries.len == 1
        let innerEntry = innerV.timeline.entries[0]
        doAssert innerEntry.procName == "grandCall"
        doAssert innerEntry.asserted == false
        doAssert innerEntry.args[".fp"] ==
          fingerprintOf("grandCall", @[$7])
        innerV.timeline.markAsserted(innerEntry)
      # Inner sandbox exit: popVerifier retires innerV (sandbox-owned,
      # retire is correct); verifyAll runs on innerV cleanly (one mock
      # consumed, one interaction asserted). A's stack back to [parentV].
      doAssert verifierStack.len == 1
    # childEntry does raw `verifierStack.pop()` after A's body returns,
    # removing parentV (borrowed). A's stack empty.

    sandbox:
      let parentV = currentVerifier()

      # Parent registers + fires + consumes outerCall on the parent thread
      # BEFORE spawning the child. The purpose is to give parentV a
      # clean, consumed lifecycle so that the key assertion below —
      # "parentV.timeline contains NO grandCall interaction" — is the
      # strongest claim we can make about parentV's state. We do NOT
      # fire outerCall anywhere on the child or grandchild — grandCall
      # is the only interaction fired on the grandchild, and it must
      # land on innerV (not parentV).
      # Sentinel 9010 distinct from real-impl result 1*10=10.
      mock.expect outerCall(1):
        respond value: 9010
      check callOuter(1) == 9010

      # Consume the parent interaction before spawning so that when we
      # later check parentV.timeline.entries.len == 1 (only the outerCall,
      # not the grandchild's grandCall), the assertion is unambiguous.
      check parentV.timeline.entries.len == 1
      let outerEntry = parentV.timeline.entries[0]
      check outerEntry.procName == "outerCall"
      parentV.timeline.markAsserted(outerEntry)

      withTripwireThread:
        childBody()

      # Parent's post-join stack invariant: verifierStack is {.threadvar.},
      # so the parent thread's stack is independent of the children's.
      # Parent's stack still holds parentV (from the outer sandbox).
      check verifierStack.len == 1
      check currentVerifier() == parentV

      # KEY ASSERTION: parentV.timeline must contain EXACTLY ONE entry —
      # the parent-thread outerCall we fired above. The grandchild's
      # grandCall interaction must NOT be on parentV.timeline. If E8
      # semantics had regressed (grandchild inheriting parentV), this
      # check would fire — parentV.timeline.entries.len would be 2, with
      # grandCall as the second entry.
      check parentV.timeline.entries.len == 1
      let onlyEntry = parentV.timeline.entries[0]
      check onlyEntry.procName == "outerCall"
      check onlyEntry.asserted == true  # already consumed above
      check onlyEntry.args[".fp"] ==
        fingerprintOf("outerCall", @[$1])
    # Parent sandbox exit: verifyAll runs on parentV, sees one consumed
    # interaction (outerCall) and no unused mocks. If the grandchild's
    # grandCall had leaked onto parentV.timeline, the above in-test
    # assertion would have already fired; verifyAll here would ALSO
    # fire UnassertedInteractionsDefect (the leaked grandCall would be
    # unasserted because only outerCall was markAsserted'd).
