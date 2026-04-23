## Q3: nil-verifier guard. The TRM raises Defect if it fires with no
## verifier on the stack. Run the Q1 leak scenario and observe where the
## exception lands.
##
## Expectation unknown: asyncCheck adds a callback that by default swallows
## exceptions unless you explicitly hook onError. We want to see if Defect
## escapes far enough to be useful as a leak tripwire.
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
  if v == nil:
    raise newException(Defect,
      "TRM fired outside any active verifier - leaked async or missing test wrapper")
  inc(v.rewriteCount)
  echo "  TRM fired against verifier: ", v.name, " count=", v.rewriteCount
  a * 2

proc asyncDelayedTarget(): Future[int] {.async.} =
  await sleepAsync(30)
  echo "  [async body resuming]"
  return target(7)

proc test1() =
  echo "== test1 =="
  discard pushVerifier("test1")
  asyncCheck asyncDelayedTarget()
  let popped = popVerifier()
  echo "  test1 popped count=", popped.rewriteCount

verifierStack = @[]
test1()

echo "-- draining dispatcher --"
# Wrap poll itself: the Defect might propagate out of poll(), or it might be
# swallowed inside the async callback chain.
try:
  poll(200)
  while hasPendingOperations():
    poll(50)
  echo "poll() returned normally"
except Defect as d:
  echo "!! Defect escaped poll(): ", d.msg
except CatchableError as e:
  echo "!! CatchableError escaped poll(): ", e.msg, " (type=", $e.name, ")"

echo "-- survived --"
echo "stack depth=", verifierStack.len
