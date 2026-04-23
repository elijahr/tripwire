## Q3: nil-verifier guard raises Defect on the worker thread.
## Does the Defect propagate back to the main thread?
## Build: nim c --threads:on -r --hint:all:off q3_defect_guard.nim

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
      "TRM fired on thread T" & $getThreadId() &
      " with no active verifier - thread spawned outside test scope?")
  inc(v.rewriteCount)
  a * 2

proc workerProc() {.thread.} =
  echo "[T", getThreadId(), "] worker about to call target(42)"
  discard target(42)
  echo "[T", getThreadId(), "] worker past target(42) - SHOULD NOT PRINT"

proc test3() =
  discard pushVerifier("test3-main")
  var t: Thread[void]
  createThread(t, workerProc)
  try:
    joinThread(t)
    echo "[T", getThreadId(), "] joinThread returned normally"
  except Exception as e:
    echo "[T", getThreadId(), "] joinThread raised ", e.name, ": ", e.msg
  echo "[T", getThreadId(), "] main still alive after join"
  let popped = popVerifier()
  echo "test3 main verifier count: ", popped.rewriteCount

test3()
echo "[main] reached end of program"
