## tests/threads/test_tripwire_thread_exception.nim — Task 3.5 exception
## propagation (Exercise E1, Metric M1, design §3.5).
##
## Exercises the exception-propagation contract of `withTripwireThread`:
## a `ValueError` raised inside the child body re-raises on the parent at
## the `withTripwireThread` call site. Under Nim 2.2.6, `joinThread`
## itself does NOT re-raise child exceptions — `threadProcWrapDispatch`
## catches unhandled exceptions and calls `threadTrouble -> rawQuit(1)`,
## killing the entire process. Design §3.5 line 405's original claim
## that exception propagation was "free from joinThread" was incorrect
## for this Nim version.
##
## Tripwire works around the stdlib gap by marshaling the child's
## exception through `ThreadHandoff.capturedExc` (commit `4d8fc4f`,
## `fix(threads): marshal child exceptions through ThreadHandoff`):
## `childEntry` wraps its entire body (including the §3.6 rejection
## checks) in `try/except Exception as e: h.capturedExc = e`, and
## `withTripwireThread` re-raises `h.capturedExc` after `joinThread`
## returns. The exception therefore surfaces on the parent at the
## call-site of the block, matching the §3.5 guarantee with tripwire-
## side machinery rather than stdlib semantics.
##
## Two test cases:
##
## 1. **Strict first-violation-wins**: the child fires a TRM (leaving an
##    unasserted timeline entry AND consuming the mock queue) and then
##    raises `ValueError`. The parent does NOT catch; the exception flies
##    out of the `sandbox` block. Sandbox's finally (src/tripwire/sandbox.nim
##    lines 55-61) sees `getCurrentException() != nil` and correctly
##    SKIPS `verifyAll` — the `ValueError` IS the verification failure,
##    and raising an `UnassertedInteractionsDefect` from a `finally`
##    would mask it. The outer `expect ValueError` confirms the original
##    exception reaches the test frame intact.
##
## 2. **Ergonomic catch**: the child fires a TRM and raises `ValueError`.
##    The parent catches, asserts message preservation, manually consumes
##    the leftover timeline entry via `markAsserted`, and lets the
##    sandbox exit cleanly. `verifyAll` runs (no in-flight exception) and
##    sees a clean timeline / fully-consumed mock queue.
##
## Compile (mirrors test_tripwire_thread_basic.nim's arc rationale):
##
##   nim c --threads:on --mm:arc -d:tripwireActive \
##         --import:tripwire/auto -r tests/threads/test_tripwire_thread_exception.nim
##
## `--mm:arc` (NOT `--gc:orc`) because Nim 2.2.6's orc cycle collector
## crashes during ref-Verifier teardown after a child thread has pushed/
## popped the shared verifier. See `spike/threads/v02_gc_safety_REPORT.md`
## (Addendum) and test_tripwire_thread_basic.nim's header for the full
## reproducer. Design §8.1 lists orc and arc as co-equal supported GCs.
##
## Design citations:
##   - §3.5 line 405: exception propagation contract ("exceptions raised
##     in body propagate to the parent"). Note: stdlib joinThread does
##     NOT provide this in Nim 2.2.6; tripwire marshals manually via
##     ThreadHandoff.capturedExc (commit 4d8fc4f).
##   - §3.5 lines 405-407: first-violation-wins / atomicity. Sandbox's
##     finally guard at `sandbox.nim:55-61` (`if getCurrentException()
##     == nil: nfV.verifyAll()`) implements this by skipping verifyAll
##     when an exception is already in flight.
##   - §3.3: handoff mechanism — `h.verifier` shared with parent, TRM
##     interactions land on parent timeline even when the child then
##     raises.
##   - §8.1: supported GCs (orc and arc are co-equal; arc selected
##     here to sidestep the orc cycle-collector teardown crash).
##
## Metric M1: threading intercepts work under `--mm:arc --threads:on`.
## Exercise E1: exception propagation through `withTripwireThread`.
##
## Mirrors `test_tripwire_thread_basic.nim` and `test_tripwire_thread_multi.nim`:
## module-scope `mockable`, a `{.gcsafe.}`-cast wrapper proc, and
## drain-verifier-stack in `setup`.
import std/[unittest, options, tables]
import tripwire/[types, timeline, sandbox, verify]
import tripwire/plugins/mock
import tripwire/threads

# User proc to be mocked. Side-effect-free so the child body running
# under `--mm:arc` touches only the shared ref Verifier (design §8).
proc computeOnThread(x: int): int =
  x * 2   # real impl; TRM intercepts this

# Module-scope TRM emission. The dummy arg (0) only provides arity/type
# for the pattern's formal params; the value is not used at runtime.
mockable(computeOnThread(0))

# Wrapper proc — matches the basic/multi tests' {.gcsafe.}-cast pattern.
# The cast is safe for the same reasons documented there: `mockPluginInstance`
# is an immutable module-scope let, verifier state is a shared ref crossed
# via ThreadHandoff (§3.3), and this test is the design's intended
# --mm:arc exercise (§8.1).
proc callComputeOnThread(x: int): int {.gcsafe.} =
  {.cast(gcsafe).}:
    computeOnThread(x)

suite "withTripwireThread: exception propagation":
  setup:
    # Drain any stack left over from a prior test's failure path.
    while currentVerifier() != nil:
      discard popVerifier()

  test "child ValueError propagates through sandbox; first-violation-wins":
    # Child body kept as a separate proc so the TRM rewrite of the
    # `computeOnThread(x)` call site inside `callComputeOnThread`'s body
    # executes in a normal proc context rather than inside the anonymous
    # closure generated by `withTripwireThread`'s body capture (see
    # basic-test header for the full rationale).
    proc childBody() {.gcsafe.} =
      # TRM fires, consumes the mock, records an unasserted interaction
      # on the shared parent timeline. The value itself is discarded —
      # the point is to leave mock-queue and timeline state behind so
      # the first-violation-wins guard has something to potentially
      # (and wrongly) re-raise over the ValueError.
      discard callComputeOnThread(7)
      # Uncaught raise on the child. Under the pre-4d8fc4f threads.nim
      # this would `rawQuit(1)` the process. Post-fix, childEntry
      # captures into h.capturedExc; withTripwireThread re-raises after
      # joinThread; the exception surfaces HERE at the block call-site.
      raise newException(ValueError, "boom from child")

    # Outer `expect ValueError` confirms the exception reaches the test
    # frame intact (i.e., sandbox's finally did NOT mask it with an
    # UnassertedInteractionsDefect / UnusedMocksDefect, per §3.5
    # first-violation-wins and the `getCurrentException == nil` guard
    # at sandbox.nim:55-61).
    expect ValueError:
      sandbox:
        mock.expect computeOnThread(7):
          respond value: 14
        withTripwireThread:
          childBody()
        # Control never reaches here — ValueError is in flight. Sandbox's
        # finally pops the verifier and evaluates
        # `getCurrentException() == nil`, which is FALSE (the ValueError
        # is the current exception), so verifyAll is SKIPPED. The
        # unconsumed mock and unasserted timeline entry left behind by
        # the crashing child are NOT re-raised as
        # UnassertedInteractionsDefect / UnusedMocksDefect — the
        # ValueError IS the verification failure.

  test "child ValueError caught on parent; manual cleanup; sandbox completes cleanly":
    # Ergonomic companion to the strict test above: demonstrates that a
    # parent CAN catch a child's exception inline, restore verifier
    # invariants by hand, and let the sandbox exit clean. Confirms both
    # (a) the marshaled exception is a first-class ValueError with its
    # message preserved and (b) the TRM that fired before the raise
    # still landed on the parent's shared timeline.
    var sawValueError = false
    proc childBody() {.gcsafe.} =
      # TRM fires before the raise, leaving an unasserted timeline entry.
      discard callComputeOnThread(11)
      raise newException(ValueError, "boom v2")

    sandbox:
      let v = currentVerifier()
      mock.expect computeOnThread(11):
        respond value: 22
      try:
        withTripwireThread:
          childBody()
      except ValueError as e:
        # The exception is the real ValueError raised on the child, not
        # a wrapped or re-typed shadow. Message preserved verbatim.
        sawValueError = true
        check e.msg == "boom v2"
      check sawValueError
      # The TRM fired on the child BEFORE the raise — §3.3 handoff means
      # that interaction lives on the shared parent timeline. Verify
      # it's there and consume it so sandbox-exit `verifyAll` (which
      # WILL run because there's no in-flight exception at this point)
      # sees a clean timeline and a fully-consumed mock queue.
      check v.timeline.entries.len == 1
      let entry = v.timeline.entries[0]
      check entry.procName == "computeOnThread"
      check entry.asserted == false
      check entry.args[".fp"] ==
        fingerprintOf("computeOnThread", @[$11])
      v.timeline.markAsserted(entry)
    # sandbox exit runs verifyAll: zero unasserted interactions, zero
    # unused mocks. This proves the marshaling didn't corrupt state:
    # the TRM consumed the mock before the raise, the raise didn't
    # leave verifier internals in a half-baked state, and manual
    # markAsserted finishes the job.
