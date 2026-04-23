## Q4: Inheritance hack - wrapped createThread that captures parent's verifier
## and pushes an inherited entry on the child's stack, then transfers counts back.
## Build: nim c --threads:on -r --hint:all:off q4_inherit.nim

import std/locks

type
  Verifier = ref object
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
  echo "[T", getThreadId(), "] TRM fired, verifier: ",
       (if v != nil: v.name else: "<NIL>")
  if v != nil: inc(v.rewriteCount)
  a * 2

# We need a shared handoff slot so the child can see the parent's verifier ref
# (thread-locals don't cross) and the parent can read the child's count back.
type Handoff = object
  parentName: string
  childCount: int

var handoffLock: Lock
initLock(handoffLock)
var handoff {.global.}: Handoff

proc childWrapper(h: ptr Handoff) {.thread.} =
  # Push a fresh inherited verifier; counts stay local to this thread.
  discard pushVerifier("inherited:" & h.parentName)
  # Do user work
  discard target(100)
  discard target(200)
  discard target(300)
  let popped = popVerifier()
  withLock handoffLock:
    h.childCount = popped.rewriteCount

proc nimfootThread(h: ptr Handoff) =
  var t: Thread[ptr Handoff]
  createThread(t, childWrapper, h)
  joinThread(t)

proc test4() =
  let parent = pushVerifier("test4-main")
  discard target(1)  # main-local call
  handoff = Handoff(parentName: parent.name, childCount: 0)
  nimfootThread(addr handoff)
  # Fold child count into parent
  parent.rewriteCount += handoff.childCount
  let popped = popVerifier()
  echo "test4 main verifier count (after fold): ", popped.rewriteCount
  echo "child recorded: ", handoff.childCount
  echo "expected total: 4 (1 main + 3 child)"

test4()
