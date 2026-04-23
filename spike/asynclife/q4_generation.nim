## Q4: generation counter / popped-but-referenced detection.
##
## Hypothesis: a leaked async closure holds a reference to the Verifier that
## was active when it was created (captured via `currentVerifier()` at TRM
## fire time — but the TRM fire happens AFTER await resume, so we actually
## capture whatever is current *then*, which is nil or wrong verifier).
##
## The real detection story: we can ALSO ask each verifier to stay alive
## (the leaked coroutine's stack still pins it via captured variables if it
## referenced it). But the TRM only consults `currentVerifier()` — the stack
## top — so a leak fires against whatever is currently on top, not the
## original verifier.
##
## What we CAN do: carry a generation counter on each Verifier. On TRM fire,
## check the generation of current vs a snapshot taken at verifier creation.
## But the TRM body only sees the current stack, not the creator's identity.
##
## The more practical pattern: have the async proc capture `currentVerifier()`
## explicitly at creation and route TRM fires through that captured ref.
## But user code writes the async proc — nimfoot can't force capture.
##
## So the only detection nimfoot gets is: (a) nil stack at TRM fire time, or
## (b) current verifier's generation != the generation stored in some
## "expected" slot. Neither catches the test1->test2 contamination case if
## the leak fires WHILE test2's verifier is on the stack, because the TRM
## sees a valid, current, live verifier.
##
## This spike tests the worst case: leak fires while test2 is still executing.
import std/asyncdispatch

var nextGeneration = 0

type Verifier = ref object
  name: string
  generation: int
  rewriteCount: int
  leakedAfterPop: int

var verifierStack {.threadvar.}: seq[Verifier]

proc pushVerifier(name: string): Verifier =
  inc(nextGeneration)
  result = Verifier(name: name, generation: nextGeneration)
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
    echo "  TRM: v.name=", v.name, " gen=", v.generation,
      " count=", v.rewriteCount
  else:
    echo "  TRM: <NIL stack>"
  a * 2

proc asyncDelayedTarget(label: string, delayMs: int): Future[int] {.async.} =
  await sleepAsync(delayMs)
  echo "  [", label, " resuming]"
  return target(7)

# Scenario A: leak fires during test2's window.
# test1 pushes v1, asyncChecks a 40ms delayed call, pops v1, returns.
# test2 pushes v2, waitFors 80ms, during which test1's leak resumes at ~40ms.
# Question: does leaked TRM hit v2 (contamination)?

var v1Snapshot, v2Snapshot: Verifier

proc testA1() =
  echo "== testA1 =="
  discard pushVerifier("A1")
  asyncCheck asyncDelayedTarget("A1-leak", 40)
  v1Snapshot = popVerifier()

proc testA2() =
  echo "== testA2 =="
  discard pushVerifier("A2")
  # Hold v2 on the stack for 80ms so the leak has time to resume while v2
  # is current.
  waitFor sleepAsync(80)
  v2Snapshot = popVerifier()

verifierStack = @[]
testA1()
testA2()
echo "-- drain --"
while hasPendingOperations():
  poll(20)

echo "-- results --"
echo "v1.count=", v1Snapshot.rewriteCount, " gen=", v1Snapshot.generation
echo "v2.count=", v2Snapshot.rewriteCount, " gen=", v2Snapshot.generation
echo "stack depth=", verifierStack.len
