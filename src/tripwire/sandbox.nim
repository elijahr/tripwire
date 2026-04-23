## tripwire/sandbox.nim — Verifier type, thread-local stack, sandbox template.
import std/[tables, monotimes]
import ./[types, timeline]

type
  Verifier* = ref object
    name*: string
    timeline*: Timeline
    mockQueues*: Table[string, MockQueue]
    context*: AssertionContext
    generation*: int
    createdAt*: MonoTime
    active*: bool

proc newVerifier*(name: string = ""): Verifier =
  Verifier(name: name, timeline: Timeline(nextSeq: 0),
           mockQueues: initTable[string, MockQueue](),
           context: AssertionContext(strict: true),
           generation: 0, createdAt: getMonoTime(), active: true)

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
