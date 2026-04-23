## nimfoot/sandbox.nim — Verifier type, thread-local stack, sandbox template.
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
  ## `verifyAll` lives in `nimfoot/verify` which imports this module;
  ## to avoid a circular `bind`, it resolves at instantiation site
  ## (caller must `import nimfoot/verify` alongside `nimfoot/sandbox`).
  bind popVerifier, pushVerifier, newVerifier
  let nfV = pushVerifier(newVerifier())
  try:
    body
  finally:
    discard popVerifier()
    nfV.verifyAll()
