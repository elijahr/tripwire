## tests/threads/test_tripwire_thread_nested_sandbox.nim — Task 3.6,
## Exercise E6 (design §3.7 lines 480-485).
##
## Pins the nested-sandbox-inside-child-thread contract: opening a FRESH
## `sandbox:` block INSIDE the body of `withTripwireThread` pushes a NEW
## verifier onto the CHILD thread's thread-local `verifierStack` for the
## duration of that inner block. Interactions fired inside the inner
## sandbox verify against the inner verifier ONLY; they do NOT mix into
## the parent verifier's timeline that the child inherited via the §3.3
## handoff.
##
## Why this matters (E6 row, design §3.7 lines 480-485): users composing
## test helpers may want to borrow `sandbox` INSIDE a threaded body to
## isolate a sub-unit of work (e.g., stubbing additional procs only for a
## narrow region of the child's execution). That must be safe — pushing
## the inner verifier, running the inner body, popping the inner verifier,
## and verifyAll-ing on inner-sandbox exit must NOT corrupt the parent
## verifier that still sits at index 0 of the child's stack, and must NOT
## leak the child's post-inner-sandbox work onto the inner verifier.
##
## The verifier-stack invariant being pinned:
##   - On child-thread entry, `childEntry` pushes the inherited parent
##     verifier (design §3.3). Child stack length: 1.
##   - Inside an inner `sandbox:` block, `sandbox`'s pushVerifier adds a
##     fresh inner verifier. Child stack length: 2 (parent at index 0,
##     inner at index 1).
##   - Inside the inner block, `currentVerifier()` resolves to the inner
##     verifier, so mock.expect and TRM-fired interactions land there.
##   - Inner sandbox's `finally` pops (via `popVerifier`, which retires
##     the inner verifier — correct here because the inner verifier is
##     NOT borrowed; `sandbox` itself allocated it). Child stack length
##     back to 1.
##   - `verifyAll` on inner sandbox exit runs against the inner verifier
##     only. The parent verifier (still at index 0) is untouched.
##   - Post-inner-sandbox interactions on the child go back to landing
##     on the parent verifier.
##   - `childEntry`'s raw `verifierStack.pop()` removes the parent (NOT
##     retiring it — it is borrowed). Child stack length: 0.
##
## Mechanism alignment with the basic/multi tests:
##   - §3.3 (handoff): parent's ref Verifier is shared with the child via
##     `ThreadHandoff`; the child pushes it onto its own thread-local
##     `verifierStack` at `childEntry`.
##   - §3.5 (multi-child / sequential topology): this test does NOT
##     spawn multiple children — just one child, with one inner sandbox
##     inside its body. But the same thread-local-stack discipline that
##     keeps §3.5 safe is the invariant pinned here: child's post-push
##     retire (raw pop) vs. sandbox's owned-verifier retire (popVerifier)
##     must remain distinct operations.
##
## Commit `f1fa982` fixed `childEntry` to use raw `verifierStack.pop()`
## (not `popVerifier()`) so that the borrowed parent verifier is NOT
## retired when the child exits. This test exercises the adjacent
## invariant: that an INNER sandbox CAN legitimately retire its OWN
## verifier via popVerifier without disturbing the still-live parent
## verifier beneath it on the child's stack.
##
## Compile (mirrors test_tripwire_thread_basic.nim's arc rationale):
##
##   nim c --threads:on --mm:arc -d:tripwireActive \
##         --import:tripwire/auto -r tests/threads/test_tripwire_thread_nested_sandbox.nim
##
## `--mm:arc` (NOT `--gc:orc`) because Nim 2.2.6's orc cycle collector
## crashes during ref-Verifier teardown after a child thread has pushed/
## popped the shared verifier. See `spike/threads/v02_gc_safety_REPORT.md`
## (Addendum) and test_tripwire_thread_basic.nim's header for the full
## reproducer. Design §8.1 lists orc and arc as co-equal supported GCs.
##
## Design citations:
##   - §3.7 lines 480-485 (E6 row): nested sandbox inside `withTripwireThread`
##     body — interactions inside the inner sandbox isolate to the inner
##     verifier; parent verifier timeline unaffected by inner-sandbox work.
##   - §3.5 (lines 409-427): multi-level handoff background — the
##     thread-local stack discipline that makes §3.5 safe is what makes
##     E6 safe here.
##   - §3.3: handoff mechanism — parent verifier shared to child via
##     `ThreadHandoff`; child pushes it on entry.
##   - §8.1: supported GCs (orc and arc co-equal; arc selected here).
##
## Metric: M1 (threading intercepts work under `--mm:arc --threads:on`).
## Not a new metric — part of M1's broader threading-correctness story.
##
## Mirrors `test_tripwire_thread_basic.nim` / `_multi.nim` / `_exception.nim`:
## module-scope `mockable`, `{.gcsafe.}`-cast wrappers, drain-verifier-stack
## in `setup`.
import std/[unittest, options, tables]
import tripwire/[types, timeline, sandbox, verify]
import tripwire/plugins/mock
import tripwire/threads

# Two distinct user procs:
#   - `outerCall` is mocked on the PARENT verifier and called from the
#     child body OUTSIDE any inner sandbox. Its interactions should land
#     on the parent timeline.
#   - `innerCall` is mocked on the INNER verifier (inside the inner
#     `sandbox:` block, on the child thread). Its interactions should
#     land on the INNER verifier's timeline ONLY — never on the parent's.
proc outerCall(x: int): int =
  x * 10   # real impl; TRM intercepts
proc innerCall(y: int): int =
  y * 100  # real impl; TRM intercepts

# Module-scope TRM emissions. Dummy args only provide arity/types.
mockable(outerCall(0))
mockable(innerCall(0))

# Wrapper procs — mirror the basic/multi/exception tests' {.gcsafe.}-cast
# pattern. The cast is safe because `mockPluginInstance` is an immutable
# module-scope let and verifier state is shared via ref; see basic-test
# header for the full rationale.
proc callOuter(x: int): int {.gcsafe.} =
  {.cast(gcsafe).}:
    outerCall(x)

proc callInner(y: int): int {.gcsafe.} =
  {.cast(gcsafe).}:
    innerCall(y)

suite "withTripwireThread: nested sandbox (E6)":
  setup:
    # Drain any stack left over from a prior test's failure path.
    while currentVerifier() != nil:
      discard popVerifier()

  test "inner sandbox inside child body isolates its timeline from parent":
    # Child body: fires outerCall BEFORE the inner sandbox, opens an
    # inner sandbox, registers a mock for innerCall, fires innerCall,
    # consumes the inner interaction inside the inner block, exits the
    # inner sandbox cleanly, then fires outerCall AGAIN post-inner-
    # sandbox. The two outerCall interactions must land on the parent
    # verifier's timeline; the innerCall interaction must land on the
    # inner verifier's timeline and NEVER on the parent's.
    proc childBody() {.gcsafe.} =
      # Child's verifierStack at entry: [parent] (len 1). Parent verifier
      # is the top. outerCall TRM resolves against parent.
      doAssert verifierStack.len == 1
      doAssert callOuter(1) == 10

      # Open an inner sandbox on the child thread. sandbox pushes a
      # fresh verifier. Child's stack: [parent, inner] (len 2). Inner
      # verifier is the top; currentVerifier() == inner.
      sandbox:
        doAssert verifierStack.len == 2
        let innerV = currentVerifier()
        doAssert not innerV.isNil

        # Register a mock on the INNER verifier. innerCall TRM resolves
        # against inner because currentVerifier() is inner here.
        mock.expect innerCall(7):
          respond value: 700
        doAssert callInner(7) == 700

        # The innerCall interaction must be on the inner verifier's
        # timeline, NOT the parent's. Consume it here so inner
        # sandbox's exit verifyAll sees a clean timeline.
        doAssert innerV.timeline.entries.len == 1
        let innerEntry = innerV.timeline.entries[0]
        doAssert innerEntry.procName == "innerCall"
        doAssert innerEntry.asserted == false
        doAssert innerEntry.args[".fp"] ==
          fingerprintOf("innerCall", @[$7])
        innerV.timeline.markAsserted(innerEntry)
      # Inner sandbox exit: sandbox's finally popped the inner verifier
      # (via popVerifier — retires it; safe because the inner verifier
      # is sandbox-owned, not borrowed), and ran verifyAll on the inner
      # verifier. Child's stack back to [parent] (len 1). Parent is
      # top; currentVerifier() is now the parent again.
      doAssert verifierStack.len == 1

      # Post-inner-sandbox: outerCall TRM resolves against parent again.
      doAssert callOuter(2) == 20

    sandbox:
      let parentV = currentVerifier()

      # Parent registers BOTH outerCall expectations BEFORE spawning the
      # child. Design §3.5 blessed ordering: no parent-side verifier
      # mutation while the child is running. innerCall is NOT registered
      # on the parent — it's registered inside the inner sandbox on the
      # child, where it resolves against the inner verifier.
      mock.expect outerCall(1):
        respond value: 10
      mock.expect outerCall(2):
        respond value: 20

      withTripwireThread:
        childBody()

      # Parent's post-join stack invariant: after withTripwireThread
      # joins, the child's raw verifierStack.pop() has removed the
      # parent verifier from the CHILD's stack — but the PARENT thread's
      # stack is a separate thread-local (verifierStack is a
      # {.threadvar.} — see sandbox.nim line 23). The parent's stack
      # still holds only its own sandbox's verifier.
      check verifierStack.len == 1
      check currentVerifier() == parentV

      # The parent timeline must contain EXACTLY the two outerCall
      # interactions fired on the child — one before the inner sandbox
      # and one after. The innerCall interaction (fired inside the inner
      # sandbox on the child) must NOT be on the parent timeline.
      check parentV.timeline.entries.len == 2

      let firstEntry = parentV.timeline.entries[0]
      check firstEntry.procName == "outerCall"
      check firstEntry.asserted == false
      check firstEntry.args[".fp"] ==
        fingerprintOf("outerCall", @[$1])

      let secondEntry = parentV.timeline.entries[1]
      check secondEntry.procName == "outerCall"
      check secondEntry.asserted == false
      check secondEntry.args[".fp"] ==
        fingerprintOf("outerCall", @[$2])

      # Consume both outerCall interactions so sandbox-exit verifyAll
      # (which runs because no exception is in flight) sees a clean
      # parent timeline and a fully-consumed parent mock queue.
      parentV.timeline.markAsserted(firstEntry)
      parentV.timeline.markAsserted(secondEntry)
    # Parent sandbox exit: verifyAll runs on parent verifier, sees zero
    # unasserted interactions and zero unused mocks. If the innerCall
    # interaction had leaked onto the parent timeline (contra §3.7 E6),
    # verifyAll here would raise UnassertedInteractionsDefect (3 entries,
    # only 2 markAsserted'd). If the parent-side outerCall expectations
    # had been resolved against the wrong verifier, verifyAll here
    # would raise UnusedMocksDefect.
