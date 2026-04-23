## Q1: asyncCheck leak across test boundary.
##
## Simulate nimfoot's per-test Verifier stack. Launch a fire-and-forget
## async that completes AFTER the test body has returned (and the verifier
## has been popped). Observe what the leaked TRM fires against.
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
  await sleepAsync(50)   # yield — test body will have returned by now
  echo "  [async body resuming after sleep]"
  return target(7)

# Track verifiers after pop so we can report their final state.
var test1Verifier: Verifier
var test2Verifier: Verifier

proc test1() =
  echo "== test1 entering =="
  discard pushVerifier("test1")
  asyncCheck asyncDelayedTarget()   # leak!
  echo "  test1 body returning (TRM not yet fired)"
  test1Verifier = popVerifier()
  echo "  test1 popped, count at pop=", test1Verifier.rewriteCount

proc test2() =
  echo "== test2 entering =="
  discard pushVerifier("test2")
  # Intentionally no target() call here — we want to see if the leak lands on us.
  echo "  test2 body returning"
  test2Verifier = popVerifier()
  echo "  test2 popped, count at pop=", test2Verifier.rewriteCount

verifierStack = @[]
test1()
test2()

echo "-- draining dispatcher --"
poll(200)
# Drain any remaining callbacks.
while hasPendingOperations():
  poll(50)

echo "-- final state --"
echo "test1.rewriteCount=", test1Verifier.rewriteCount
echo "test2.rewriteCount=", test2Verifier.rewriteCount
echo "stack depth=", verifierStack.len
