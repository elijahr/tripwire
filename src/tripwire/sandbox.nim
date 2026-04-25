## tripwire/sandbox.nim — Verifier type, thread-local stack, sandbox template.
import std/[tables, monotimes]
import ./[types, timeline, errors]
import ./async_registry_types

type
  PassthroughPredicate* = proc(procName, fingerprint: string): bool {.closure, gcsafe.}
    ## Per-sandbox passthrough decision proc. Registered via
    ## `sandbox.passthrough(plugin, predicate)` from inside a `sandbox:`
    ## body. Returns `true` to allow an unmocked call to fall through to
    ## its real implementation (spy mode); `false` to defer to the next
    ## predicate (or, if none match, raise `UnmockedInteractionDefect`).

  PassthroughEntry* = object
    plugin*: Plugin
    predicate*: PassthroughPredicate

  Verifier* = ref object
    name*: string
    timeline*: Timeline
    mockQueues*: Table[string, MockQueue]
    context*: AssertionContext
    generation*: int
    createdAt*: MonoTime
    active*: bool
    futureRegistry*: seq[RegisteredFuture]
    passthroughPredicates*: seq[PassthroughEntry]
      ## Per-sandbox predicates registered via `sandbox.passthrough(...)`.
      ## Lifetime is bounded by the verifier: pushed in `sandbox:` template,
      ## freed when the verifier is popped. Consulted by
      ## `tripwirePluginIntercept` (and the typed-form combinator in
      ## `tripwire/intercept`) before raising `UnmockedInteractionDefect`.

proc newVerifier*(name: string = ""): Verifier =
  Verifier(name: name, timeline: Timeline(nextSeq: 0),
           mockQueues: initTable[string, MockQueue](),
           context: AssertionContext(strict: true),
           generation: 0, createdAt: getMonoTime(), active: true,
           passthroughPredicates: @[])

var verifierStack* {.threadvar.}: seq[Verifier]

proc pushVerifier*(v: Verifier): Verifier =
  verifierStack.add(v)
  v

proc popVerifier*(): Verifier =
  doAssert verifierStack.len > 0, "popVerifier called on empty stack"
  result = verifierStack.pop()
  inc(result.generation)
  result.active = false

proc currentVerifier*(): Verifier {.inline.} =
  if verifierStack.len == 0: nil else: verifierStack[^1]

proc passthrough*(plugin: Plugin, predicate: PassthroughPredicate) =
  ## Register a per-sandbox passthrough predicate against the current
  ## verifier. The predicate is consulted whenever a call routed
  ## through `plugin` finds no matching mock; if the predicate returns
  ## `true` for `(procName, fingerprint)` the call falls through to its
  ## real implementation (spy mode).
  ##
  ## Predicates are scoped to the active verifier and are released when
  ## the sandbox exits. Multiple predicates may be registered against
  ## the same plugin; the OR of the registered predicates plus the
  ## plugin's own `passthroughFor` decides passthrough.
  ##
  ## Raises `LeakedInteractionDefect` if called outside an active
  ## sandbox: registering a passthrough has no observable effect once
  ## the sandbox has been popped, so the call is treated as a leak in
  ## the same sense `tripwirePluginIntercept` does for unguarded TRMs.
  let v = currentVerifier()
  if v.isNil:
    raise newLeakedInteractionDefect(getThreadId(), instantiationInfo())
  v.passthroughPredicates.add(PassthroughEntry(plugin: plugin,
                                                predicate: predicate))

proc sandboxPassthroughFor*(v: Verifier, plugin: Plugin,
                            procName, fingerprint: string): bool =
  ## OR over all per-sandbox predicates registered against `plugin` (by
  ## ref identity). Returns `true` on the first match. Used by the
  ## TRM-body combinators to extend the existing
  ## `plugin.passthroughFor(procName)` gate with a per-sandbox,
  ## fingerprint-aware decision.
  if v.isNil:
    return false
  for entry in v.passthroughPredicates:
    if entry.plugin == plugin and entry.predicate(procName, fingerprint):
      return true
  false

template sandbox*(body: untyped) =
  ## Lexical scope: push fresh verifier, run body, pop, verifyAll.
  ## `verifyAll` lives in `tripwire/verify` which imports this module;
  ## to avoid a circular `bind`, it resolves at instantiation site
  ## (caller must `import tripwire/verify` alongside `tripwire/sandbox`).
  ##
  ## **First-violation-wins semantics.** If the body raises (e.g., a TRM
  ## fired `UnmockedInteractionDefect`), that defect IS the verification
  ## failure — we pop the verifier but do NOT re-run `verifyAll`, because
  ## a second raise inside a `finally` would mask the original with a
  ## spurious `UnassertedInteractionsDefect` (the timeline entry for the
  ## unmocked call is unasserted by definition, since the body never
  ## reached the `assert` clause). Only run `verifyAll` on normal
  ## completion, where it reports the first unmet guarantee.
  bind popVerifier, pushVerifier, newVerifier, getCurrentException
  let nfV = pushVerifier(newVerifier())
  try:
    body
  finally:
    discard popVerifier()
    # First-violation-wins: if an exception (including Defect) is already
    # in flight from body, don't re-run verifyAll — doing so would raise
    # UnassertedInteractionsDefect inside a `finally`, masking the
    # original (and more informative) failure.
    if getCurrentException() == nil:
      nfV.verifyAll()

template sandbox*(name: static string, body: untyped) =
  ## Named variant: labels the fresh verifier so error messages carry
  ## the user-provided name. Semantics otherwise identical to
  ## `sandbox*(body)`; see its docstring for first-violation-wins details.
  bind popVerifier, pushVerifier, newVerifier, getCurrentException
  let nfV = pushVerifier(newVerifier(name))
  try:
    body
  finally:
    discard popVerifier()
    if getCurrentException() == nil:
      nfV.verifyAll()
