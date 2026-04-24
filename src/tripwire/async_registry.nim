## tripwire/async_registry.nim — asyncdispatch Future registration
## surface for sandboxed tests (design §4.1 lines 546-605).
##
## Exposes two templates:
##
## * ``asyncCheckInSandbox*[T](fut: Future[T])`` — register an
##   asyncdispatch ``Future[T]`` with the current verifier's
##   ``futureRegistry`` and call ``asyncCheck`` so the dispatcher
##   tracks it too. Raises ``LeakedInteractionDefect`` when no
##   verifier is on the stack (consistent with TRM-fires-outside-a-
##   sandbox semantics). Chronos Futures are rejected at compile
##   time via ``{.warning.}``; see §11 non-goals.
##
## * ``withAsyncSandbox*(body: untyped)`` — pure readability shim
##   around a group of ``asyncCheckInSandbox`` calls.
##
## **DR1 dependency graph (acyclic):**
## ``sandbox → async_registry_types ← async_registry``.
## This module imports ``sandbox`` (for ``Verifier`` /
## ``currentVerifier``) AND ``async_registry_types`` (for
## ``RegisteredFuture``). ``sandbox`` imports only
## ``async_registry_types`` (for the ``futureRegistry`` field type).
## No cycle.
##
## **Consumer-import requirement:** downstream modules that invoke
## ``asyncCheckInSandbox`` MUST ``import std/asyncdispatch``
## alongside ``tripwire/async_registry``. Even though the template
## ``bind``s ``asyncCheck`` so the library-resolved symbol wins over
## any user shadow, the ``Future[T]`` parameter in the expanded
## template still needs ``asyncdispatch``-level type resolution in
## the consumer's compilation unit. Omitting the import produces a
## compile error at the consumer call site, not here.

import std/[asyncfutures, asyncdispatch]
import ./[sandbox, errors, async_registry_types]

template asyncCheckInSandbox*[T](fut: Future[T]): untyped =
  ## Register ``fut`` with the current verifier's ``futureRegistry``
  ## AND call ``asyncCheck`` under the hood so the dispatcher tracks
  ## the Future too.
  ##
  ## Implemented as a generic template (not a proc) so that:
  ##
  ## (a) ``instantiationInfo`` captures the USER'S call site, not
  ##     the library's;
  ## (b) we can discriminate asyncdispatch Futures from chronos
  ##     Futures at compile time via ``when`` on the type parameter.
  ##
  ## Raises ``LeakedInteractionDefect`` if there is no active
  ## verifier (consistent with TRM fires outside a sandbox).
  ##
  ## Compile-time note: if the concrete Future instance is a chronos
  ## Future, the template emits a ``{.warning.}`` and does NOT
  ## register it — chronos Futures are not drainable via
  ## ``asyncdispatch.poll`` (§11 non-goal). The user is directed to
  ## chronos's native ``waitFor`` pattern inside the sandbox body.
  ##
  ## **Consumer import requirement:** downstream modules that invoke
  ## ``asyncCheckInSandbox`` MUST ``import std/asyncdispatch``
  ## (for type-level ``Future[T]`` resolution at the consumer's call
  ## site, even though this module ``bind``s ``asyncCheck``).
  mixin currentVerifier
  bind RegisteredFuture, FutureBase, newLeakedInteractionDefect,
       getThreadId, instantiationInfo, asyncCheck, stderr
  # Deviation from design §4.1 line 577: the literal `when defined(chronos)
  # and fut is chronos.Future[T]` does not compile — Nim's `when` evaluates
  # both operands of `and`, so `chronos.Future` must parse even when
  # `-d:chronos` is absent. We nest the `when`s instead (matching the
  # established idiom in `futures.nim:51-53`); behavior is identical.
  when defined(chronos):
    when fut is chronos.Future[T]:
      {.warning: "asyncCheckInSandbox does not support chronos Futures in v0.2. " &
                 "Use `discard waitFor fut` inside the sandbox body, or asyncdispatch. " &
                 "See v0.2 design §11 non-goals and docs/roadmap-v0.3.md.".}
      discard  # no registration, no asyncCheck — chronos dispatcher handles it
    else:
      let v = currentVerifier()
      if v.isNil:
        raise newLeakedInteractionDefect(
          getThreadId(), instantiationInfo())
      v.futureRegistry.add RegisteredFuture(
        fut: FutureBase(fut),
        site: instantiationInfo(fullPaths = true))
      if v.futureRegistry.len == 10_000:
        stderr.writeLine(
          "tripwire: futureRegistry has 10,000 entries on verifier '" &
          v.name & "' — consider whether all spawns are intended.")
      asyncCheck(fut)
  else:
    let v = currentVerifier()
    if v.isNil:
      raise newLeakedInteractionDefect(
        getThreadId(), instantiationInfo())
    v.futureRegistry.add RegisteredFuture(
      fut: FutureBase(fut),
      site: instantiationInfo(fullPaths = true))
    # Runtime diagnostic for pathological registries. NOTE: `{.hint.}` is a
    # compile-time pragma; we cannot emit it conditional on a runtime count.
    # Instead we write a line to stderr once per verifier when the count
    # crosses the threshold.
    if v.futureRegistry.len == 10_000:
      stderr.writeLine(
        "tripwire: futureRegistry has 10,000 entries on verifier '" &
        v.name & "' — consider whether all spawns are intended.")
    asyncCheck(fut)  # dispatcher sees it; plain asyncCheck semantics preserved

template withAsyncSandbox*(body: untyped) =
  ## Ergonomic block scope for a group of ``asyncCheckInSandbox``
  ## calls. Semantically equivalent to plain sequential calls;
  ## exists for readability and lexical grouping.
  body
