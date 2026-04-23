## Q1: Default thread-local verifier stack behavior with createThread.
## Build: nim c --threads:on -r --hint:all:off q1_create_thread.nim

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
  echo "[T", getThreadId(), "] TRM fired, verifier: ",
       (if v != nil: v.name else: "<NIL>")
  if v != nil: inc(v.rewriteCount)
  a * 2

proc workerProc() {.thread.} =
  discard target(10)
  discard target(20)

proc test1() =
  discard pushVerifier("test1-main")
  echo "[T", getThreadId(), "] main about to call target(5)"
  discard target(5)  # should fire against main verifier
  var t: Thread[void]
  createThread(t, workerProc)
  joinThread(t)
  echo "[T", getThreadId(), "] main about to call target(6) after join"
  discard target(6)  # main verifier again
  let popped = popVerifier()
  echo "test1 main verifier count: ", popped.rewriteCount
  echo "expected if main-only counted: 2; if all counted: 4"

test1()
