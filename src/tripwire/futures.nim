## tripwire/futures.nim — Future construction helpers.
##
## Runtime helpers for Future construction. Plugin async TRMs MUST call
## `makeCompletedFuture` / `makeFailedFuture` rather than inlining
## `newFuture` + `complete`. This is a deliberate workaround for
## chronos's `complete` template lexical-position issue (spike #6 Q4):
## by delegating to a runtime proc, the TRM pattern matcher never sees
## chronos's internal `getSrcLocation` call, which otherwise composes
## badly with Nim's term-rewriting macro expansion.
##
## Exports `std/asyncdispatch` by default. When compiled with
## `-d:chronos`, additionally exports `chronos` and the `Chronos`
## variant helpers.
##
## Defense 6 (pending-async leak detection) reads `hasPendingOperations`;
## when `-d:chronosFutureTracking` is enabled alongside `-d:chronos`,
## the chronos `pendingFuturesCount()` check is OR'd in. See design §9,
## §10.
import std/asyncdispatch
# Re-export asyncdispatch's public surface (Future[T], newFuture, waitFor,
# await, complete, fail, read, etc.) EXCEPT `hasPendingOperations`, which
# tripwire intentionally wraps below to OR in chronos's pending-count when
# compiled with `-d:chronos -d:chronosFutureTracking`. Plain re-export
# would shadow our wrapper and re-create the ambiguity.
export asyncdispatch except hasPendingOperations

proc makeCompletedFuture*[T](value: sink T,
                             label: string = ""): Future[T] {.raises: [].} =
  ## Build a Future[T] already completed with `value`. `label` is an
  ## optional debug tag forwarded to `newFuture[T]`.
  ##
  ## The unqualified `Future[T]` here resolves to `asyncdispatch.Future`
  ## because `import chronos` is positioned BELOW this proc — see the
  ## comment on the chronos-import block. Re-ordering risks ambiguity.
  ##
  ## `raises: []` is load-bearing for plugin TRM raises composition.
  ## `complete` (asyncdispatch) declares `raises: [ValueError]` because
  ## it raises if the future is already finished — but `newFuture[T]`
  ## above produces a freshly-allocated, not-yet-finished future, so
  ## that branch is unreachable here. We swallow the impossible
  ## ValueError so plugin `realize` overrides that delegate to this
  ## helper can be `{.raises: [Defect].}`-annotated and compose with
  ## strict-raises consumer procs.
  result = newFuture[T](label)
  # `except Exception:` is load-bearing here: `asyncdispatch.complete`
  # declares no raises clause, so Nim infers its raises set as `Exception`
  # (callbacks could raise anything in principle). `except CatchableError`
  # would NOT satisfy the effect tracker because Defect is a sibling of
  # CatchableError under Exception, and `Exception` is what `complete`
  # is inferred to raise. Wrap the block in a local
  # `{.push warning[BareExcept]:off.}` so the `--define:tripwireActive`
  # CI build does not emit the BareExcept hint at every consumer call
  # site that imports this proc transitively.
  {.push warning[BareExcept]:off.}
  try:
    result.complete(value)
  except Exception:
    discard  # unreachable on a fresh future:
             # On a freshly-`newFuture`d Future no callbacks are
             # registered, so neither the `checkFinished` ValueError
             # nor any callback exception can fire here. We swallow the
             # impossible `Exception` so plugin `realize` overrides that
             # delegate to this helper can be `{.raises: [Defect].}`-
             # annotated and compose with strict-raises consumer procs.
  {.pop.}

proc makeFailedFuture*[T](err: ref Exception,
                          label: string = ""): Future[T] {.raises: [].} =
  ## Build a Future[T] already failed with `err`. Awaiting or
  ## `waitFor`-ing the future re-raises `err`.
  ##
  ## See note on `makeCompletedFuture` re: unqualified `Future[T]` and
  ## the `raises: []` rationale (impossible-ValueError suppression on a
  ## freshly-minted future).
  result = newFuture[T](label)
  # See `makeCompletedFuture` for the full rationale on why
  # `except Exception:` is required here (asyncdispatch.fail has no
  # raises clause -> inferred `Exception`) and why we suppress the
  # BareExcept hint locally rather than narrowing to CatchableError.
  {.push warning[BareExcept]:off.}
  try:
    result.fail(err)
  except Exception:
    discard  # unreachable on a fresh future.
  {.pop.}

# `import chronos` is positioned HERE — after the unqualified-`Future[T]`
# helpers above (which need `Future` to resolve to asyncdispatch.Future),
# but before `hasPendingOperations` below (which needs
# `chronos.pendingFuturesCount` in scope under
# `-d:chronos -d:chronosFutureTracking`). Folding this with the second
# `when defined(chronos):` block below would force the helpers above to
# qualify every `Future` reference; keeping it here is the minimal change.
when defined(chronos):
  import chronos

proc hasPendingOperations*(): bool =
  ## True if the async dispatcher has outstanding callbacks.
  ##
  ## asyncdispatch is always queried via its boolean-only API. When
  ## `-d:chronos` AND `-d:chronosFutureTracking` are both set, chronos's
  ## `pendingFuturesCount()` (plural — see
  ## `chronos/internal/asyncengine.nim`) is OR'd in. Without
  ## `chronosFutureTracking`, chronos's pending count is unobservable
  ## and we conservatively report the asyncdispatch count only.
  result = asyncdispatch.hasPendingOperations()
  when defined(chronos):
    when defined(chronosFutureTracking):
      result = result or chronos.pendingFuturesCount() > 0

when defined(chronos):
  export chronos

  # Chronos's `newFuture[T]` is a template whose `fromProc` parameter is
  # typed `static[string]` — it MUST be a compile-time constant. The
  # runtime `label` parameter accepted by these helpers is therefore
  # absorbed (passed through to `asyncdispatch`'s `newFuture` in the
  # non-chronos branch, documented here). We pass a constant debug tag
  # to `chronos.newFuture` so stack traces still carry a recognizable
  # origin.
  const
    chronosMakeCompletedLabel = "tripwire.makeCompletedFutureChronos"
    chronosMakeFailedLabel    = "tripwire.makeFailedFutureChronos"

  proc makeCompletedFutureChronos*[T](value: sink T,
      label: string = ""): chronos.Future[T] =
    ## Chronos analogue of `makeCompletedFuture`. Only present under
    ## `-d:chronos`. The return type is `chronos.Future[T]`, a distinct
    ## type from `asyncdispatch.Future[T]`.
    ##
    ## The `label` parameter is accepted for API symmetry with
    ## `makeCompletedFuture` but is not forwarded to `chronos.newFuture`
    ## (whose `fromProc` is `static[string]`). A constant debug tag is
    ## used instead; the runtime label is ignored.
    discard label  # silence unused-parameter warning
    result = chronos.newFuture[T](chronosMakeCompletedLabel)
    chronos.complete(result, value)

  proc makeFailedFutureChronos*[T](err: ref CatchableError,
      label: string = ""): chronos.Future[T] =
    ## Chronos analogue of `makeFailedFuture`. Only present under
    ## `-d:chronos`.
    ##
    ## Note: chronos's `fail` templates require `ref CatchableError`
    ## (stricter than asyncdispatch's `ref Exception`). Callers passing
    ## a plain `ref Exception` must narrow the type themselves.
    ## The `label` parameter is accepted for API symmetry; see the
    ## corresponding note on `makeCompletedFutureChronos`.
    discard label
    result = chronos.newFuture[T](chronosMakeFailedLabel)
    chronos.fail(result, err)
