## tripwire/threads.nim — Verifier-inheriting thread primitives.
##
## Public surface:
##   - `ThreadHandoff`      — heap-allocated handoff record (parent → child)
##   - `tripwireThread`     — low-level drop-in replacement for `createThread`
##   - `runWithVerifier`    — explicit-verifier-param escape hatch
##   - `withTripwireThread` — canonical ergonomic wrapper
##   - `childEntry`         — child-thread entry used by `withTripwireThread`
##
## Design citations: v0.2 design §3.2 (this module's code), §3.3 (handoff
## sequence), §3.6 (rejection order), §8.1 (GC-safety & refc decision
## recorded in spike/threads/v02_gc_safety_REPORT.md).

# F1: --threads:off is unsupported. The primitives in this module are
# meaningless without OS threads.
when not compileOption("threads"):
  {.error: "tripwireThread requires --threads:on".}

# F2: refc + threads is rejected at compile time (§8 decision). Attempting
# to build this module under --gc:refc --threads:on yields a loud error
# with a roadmap pointer. refc's thread-local heaps drop child mutations
# to the shared ref Verifier, so verifier inheritance is unsafe.
when defined(gcRefc) and compileOption("threads"):
  {.error: "tripwireThread requires --gc:orc or --gc:arc; " &
           "refc thread-local heaps drop child mutations to the shared " &
           "ref Verifier. See v0.2 design §8 and docs/roadmap-v0.3.md.".}

# `./futures` re-exports asyncdispatch (except hasPendingOperations) and
# provides tripwire's own `hasPendingOperations` wrapper that ORs in
# chronos's pending count under `-d:chronosFutureTracking`. Importing
# asyncdispatch directly here would re-introduce the ambiguity.
import ./[sandbox, errors, futures]

type
  ThreadHandoff* = ref object
    ## Heap-allocated handoff record crossed through createThread's data arg.
    ## MUST be heap-allocated (ref object) so the child can safely dereference
    ## after the parent's stack frame where it was constructed has progressed.
    verifier*: Verifier         ## ref Verifier — inherited parent state
    body*: proc() {.gcsafe.}    ## closure capturing the user body.
    capturedExc*: ref Exception ## any exception raised by `body` or by
                                ## childEntry's rejection checks; the parent
                                ## re-raises this AFTER joinThread. Required
                                ## because Nim 2.2.6's joinThread does NOT
                                ## propagate child exceptions: `threadProcWrapDispatch`
                                ## catches unhandled exceptions and calls
                                ## `threadTrouble` -> `rawQuit(1)`, killing
                                ## the entire process. Without explicit
                                ## marshaling, design §3.5's "exception
                                ## propagation" guarantee (E1) and the
                                ## §3.6 rejection defects (chronos / nested)
                                ## would never reach the parent.
                                ## Intentionally `{.gcsafe.}` only (no `thread`
                                ## / `nimcall`): the closure is invoked from
                                ## inside `childEntry` (which is itself
                                ## `{.thread, nimcall, gcsafe.}`) rather than
                                ## being passed as a proc pointer to
                                ## `createThread`. The calling-convention
                                ## requirement applies to the entry proc, not
                                ## to nested closures.

proc tripwireThread*[T](
    thr: var Thread[T],
    fn: proc(data: T) {.thread, nimcall, gcsafe.},
    data: T
) {.raises: [ResourceExhaustedError].} =
  ## Low-level drop-in replacement for `createThread`. Argument order
  ## matches stdlib `createThread(t, fn, arg)` exactly so the substitution
  ## is mechanical. Caller retains ownership of `thr` and must call
  ## `joinThread(thr)` themselves.
  ##
  ## `fn` runs on the new thread; it receives `data` identically to
  ## `createThread`. `fn` MUST carry `{.thread, nimcall, gcsafe.}`; the
  ## `nimcall` calling convention matches stdlib and permits passing
  ## non-closure procs across threads.
  ##
  ## IMPORTANT: `fn` is responsible for pushing the parent verifier onto
  ## its verifierStack via `runWithVerifier`. If you want verifier
  ## inheritance at this level, wrap your body with `runWithVerifier`:
  ##
  ##    proc workerBody(data: MyData) {.thread, nimcall.} =
  ##      runWithVerifier(data.verifier):
  ##        realWork(data)
  ##
  ## `withTripwireThread` does this wrapping automatically.
  ##
  ## Raises `ResourceExhaustedError` if the OS cannot allocate a thread.
  createThread(thr, fn, data)

template runWithVerifier*(v: Verifier; body: untyped) =
  ## Explicit-verifier-param escape hatch. Pushes `v` onto the current
  ## thread's verifierStack, runs `body`, pops on exit (balanced even on
  ## exception). Use this when the canonical `withTripwireThread` block
  ## is too restrictive — e.g., for thread-pool workers that receive a
  ## verifier through a channel.
  ##
  ## Invariant: on entry the current thread's verifierStack MUST be empty
  ## (otherwise raises NestedTripwireThreadDefect). On exit the stack is
  ## guaranteed empty again.
  ##
  ## Not intended for nested use within an already-sandboxed context on
  ## the SAME thread — see §3.6.
  bind verifierStack, pushVerifier,
       newNestedTripwireThreadDefect, getThreadId, instantiationInfo
  if verifierStack.len > 0:
    raise newNestedTripwireThreadDefect(
      getThreadId(), instantiationInfo())
  discard pushVerifier(v)
  try:
    body
  finally:
    # Raw stack pop — NOT popVerifier(). popVerifier() retires the verifier
    # (gen++, active=false) which is correct at sandbox exit but WRONG here:
    # `v` is borrowed (parent still owns the ref). Mutating it would
    # invalidate the parent's verifier mid-sandbox.
    discard verifierStack.pop()

proc childEntry*(h: ThreadHandoff) {.thread, nimcall, gcsafe.} =
  ## INTERNAL — referenced only via the withTripwireThread template; do not call directly
  ## Child-thread entry point used by `withTripwireThread`.
  ## Order matters: defensive stack check → chronos check → pushVerifier
  ## → body → raw verifierStack.pop(). The pushVerifier must happen AFTER
  ## the rejection checks so that a rejected child never contaminates
  ## verifierStack. The pop is the raw stack op, NOT popVerifier(), because
  ## h.verifier is borrowed from the parent (see runWithVerifier).
  ## ALL exceptions (including Defects from rejection checks) are captured
  ## into h.capturedExc and re-raised by the parent after joinThread —
  ## see ThreadHandoff.capturedExc for why this is required.
  try:
    # Defensive: a fresh thread's verifierStack should be empty by
    # language semantics ({.threadvar.} is zero-initialized per thread).
    # A non-empty stack indicates a nested tripwireThread invocation.
    if verifierStack.len > 0:
      raise newNestedTripwireThreadDefect(
        getThreadId(), instantiationInfo())
    # Chronos / dispatcher detection BEFORE pushVerifier and BEFORE body.
    # See §3.6 Rejection 1.
    if hasPendingOperations():
      raise newChronosOnWorkerThreadDefect(
        getThreadId(), instantiationInfo())
    discard pushVerifier(h.verifier)
    try:
      h.body()
    finally:
      # Raw stack pop — see runWithVerifier above. popVerifier() retires the
      # verifier; here `h.verifier` is borrowed from the parent's sandbox, so
      # retiring it would break subsequent withTripwireThread blocks in the
      # same parent sandbox (design §3.5 multi-child pattern).
      discard verifierStack.pop()
  except Exception as e:
    # Marshal to parent for re-raise after joinThread. Must be the OUTERMOST
    # try, including the rejection checks above, so chronos / nested defects
    # also surface on the parent (design §3.6 rejections E4, F4). Without
    # this catch, Nim's threadProcWrapDispatch would call rawQuit(1).
    h.capturedExc = e

template withTripwireThread*(threadBody: untyped) =
  ## Canonical ergonomic wrapper:
  ## 1. captures `currentVerifier()` on the parent
  ## 2. spawns a new thread via `tripwireThread`
  ## 3. child entry proc (`childEntry`, below) runs rejection checks,
  ##    pushes the parent verifier, and invokes the captured body
  ## 4. parent awaits joinThread before returning control to caller
  ## 5. parent does NOT mutate the verifier while the child runs (design invariant)
  ## Exceptions raised in `body` propagate to the parent via `joinThread`.
  ##
  ## Raises:
  ##   - `ChronosOnWorkerThreadDefect` if a dispatcher has pending work
  ##     on the child thread (§3.6)
  ##   - `NestedTripwireThreadDefect` if child's verifierStack is non-empty
  ##     on entry (§3.6)
  ##   - `LeakedInteractionDefect` if there is no active parent verifier
  ##   - any exception raised by `body` (re-raised after joinThread)
  bind currentVerifier, newLeakedInteractionDefect,
       ThreadHandoff, childEntry, tripwireThread,
       GC_ref, GC_unref, joinThread, Thread,
       getThreadId, instantiationInfo
  let parentV = currentVerifier()
  if parentV.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  let h = ThreadHandoff(
    verifier: parentV,
    body: proc() {.gcsafe.} = threadBody)
  GC_ref(h)
  var thr: Thread[ThreadHandoff]
  try:
    tripwireThread(thr, childEntry, h)
    joinThread(thr)
    # Re-raise any exception captured by childEntry. joinThread is a
    # synchronization barrier — h.capturedExc is fully written by the
    # child before joinThread returns. See ThreadHandoff.capturedExc
    # for why marshaling is required (Nim 2.2.6's joinThread does NOT
    # propagate child exceptions on its own).
    if not h.capturedExc.isNil:
      raise h.capturedExc
  finally:
    GC_unref(h)
