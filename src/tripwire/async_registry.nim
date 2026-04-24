## tripwire/async_registry.nim — asyncdispatch Future registration
## surface for sandboxed tests (design §4.1 lines 546-605).
##
## Exposes two templates:
##
## * ``asyncCheckInSandbox*[T](futArg: Future[T])`` — register an
##   asyncdispatch ``Future[T]`` with the current verifier's
##   ``futureRegistry`` and call ``asyncCheck`` so the dispatcher
##   tracks it too. Raises ``LeakedInteractionDefect`` when no
##   verifier is on the stack (consistent with TRM-fires-outside-a-
##   sandbox semantics). A sibling overload (active only under
##   ``-d:chronos``) accepts ``chronos.Future[T]`` and emits a
##   compile-time ``{.warning.}`` instead of registering — chronos
##   Futures are a §11 non-goal in v0.2. The two overloads are split
##   because the asyncdispatch signature strictly binds
##   ``asyncdispatch.Future``; a single template would raise a hard
##   type-mismatch error on chronos Futures before any inner ``when``
##   branch could fire the warning.
##   (Parameter is ``futArg``, not ``fut``, to avoid a Nim
##   template-hygiene collision with the ``RegisteredFuture.fut``
##   field name — see the template's doc block.)
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

template asyncCheckInSandbox*[T](futArg: Future[T]): untyped =
  ## Register ``futArg`` with the current verifier's ``futureRegistry``
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
  ##
  ## Implementation note: the template parameter is named ``futArg``
  ## rather than ``fut`` to avoid a Nim template-hygiene collision with
  ## ``RegisteredFuture.fut`` (the object-constructor field name).
  ## When the parameter name matches the field name, Nim's hygienic
  ## substitution causes the construction ``RegisteredFuture(fut: ...)``
  ## to fail to parse at callers that pass an identifier other than
  ## ``fut``. Renaming the parameter sidesteps this and lets callers use
  ## any identifier.
  mixin currentVerifier
  bind RegisteredFuture, FutureBase, newLeakedInteractionDefect,
       getThreadId, instantiationInfo, asyncCheck, stderr
  # Asyncdispatch-Future path. The chronos-Future path is a separate
  # overload defined below under `when defined(chronos)`; it emits a
  # compile-time `{.warning.}` and performs no registration. Keeping the
  # two paths as distinct overloads avoids dead-branch `when` inside a
  # hot template AND sidesteps the original problem where the
  # `futArg: Future[T]` signature bound strictly to `asyncdispatch.Future`
  # and rejected `chronos.Future` with a type-mismatch error BEFORE any
  # inner `when` branch could fire the warning (see Task 4.7, 2026-04-24).
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(
      getThreadId(), instantiationInfo())
  v.futureRegistry.add RegisteredFuture(
    fut: FutureBase(futArg),
    site: instantiationInfo(fullPaths = true))
  # Runtime diagnostic for pathological registries. NOTE: `{.hint.}` is a
  # compile-time pragma; we cannot emit it conditional on a runtime count.
  # Instead we write a line to stderr once per verifier when the count
  # crosses the threshold.
  if v.futureRegistry.len == 10_000:
    stderr.writeLine(
      "tripwire: futureRegistry has 10,000 entries on verifier '" &
      v.name & "' — consider whether all spawns are intended.")
  asyncCheck(futArg)  # dispatcher sees it; plain asyncCheck semantics preserved

when defined(chronos):
  import chronos as chronosmod

  template asyncCheckInSandbox*[T](futArg: chronosmod.Future[T]): untyped =
    ## Chronos-Future overload. Emits a compile-time ``{.warning.}``
    ## directing users to chronos's native ``waitFor`` pattern and
    ## performs NO registration (the chronos dispatcher tracks its own
    ## Futures). Defined as a separate overload rather than a `when`
    ## branch inside the asyncdispatch template because the
    ## `futArg: Future[T]` signature on the primary template binds
    ## strictly to ``asyncdispatch.Future`` — a `chronos.Future` argument
    ## would raise a "type mismatch" error BEFORE any inner `when` could
    ## see it. See design §11 (chronos non-goal) and §4.1.
    {.warning: "asyncCheckInSandbox does not support chronos Futures in v0.2. " &
               "Use `discard waitFor fut` inside the sandbox body, or asyncdispatch. " &
               "See v0.2 design §11 non-goals and docs/roadmap-v0.3.md.".}
    discard futArg  # no registration, no asyncCheck — chronos dispatcher handles it

template withAsyncSandbox*(body: untyped) =
  ## Ergonomic block scope for a group of ``asyncCheckInSandbox``
  ## calls. Semantically equivalent to plain sequential calls;
  ## exists for readability and lexical grouping.
  body
