## Q2: control case — waitFor inside the test body.
##
## This is the "safe" async shape. The test body blocks until the async
## completes, so the TRM fires while the verifier is still on the stack.
import std/asyncdispatch

type Verifier = ref object
  name: string
  rewriteCount: int

var verifierStack {.threadvar.}: seq[Verifier]

proc pushVerifier(name: string): Verifier =
  result = Verifier(name: name)
  verifierStack.add(result)

proc popVerifier(): Verifier =
  result = verifierStack.pop()

proc currentVerifier(): Verifier =
  if verifierStack.len > 0: verifierStack[^1] else: nil

proc target*(x: int): int = x * 2

template rewriteTarget*{target(a)}(a: int): int =
  let v = currentVerifier()
  if v != nil:
    inc(v.rewriteCount)
  echo "  TRM fired against verifier: ",
    (if v != nil: v.name & " (count now " & $v.rewriteCount & ")" else: "<NIL>")
  a * 2

proc asyncDelayedTarget(): Future[int] {.async.} =
  await sleepAsync(20)
  return target(7)

var verifierSnapshot: Verifier

proc testSafe() =
  echo "== testSafe entering =="
  discard pushVerifier("safe")
  let r = waitFor asyncDelayedTarget()   # block until async completes
  echo "  testSafe got r=", r
  verifierSnapshot = popVerifier()
  echo "  testSafe popped, count=", verifierSnapshot.rewriteCount

verifierStack = @[]
testSafe()
echo "-- final --"
echo "safe.rewriteCount=", verifierSnapshot.rewriteCount
echo "stack depth=", verifierStack.len
