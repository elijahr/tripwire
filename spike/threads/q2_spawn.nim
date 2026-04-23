## Q2: spawn / FlowVar behavior with thread-local verifier stack.
## Build: nim c --threads:on -r --hint:all:off q2_spawn.nim

import std/threadpool

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

proc workerSpawn(): int {.gcsafe.} =
  result = target(99)

proc test2() =
  discard pushVerifier("test2-main")
  discard target(1)  # main-thread baseline
  let fv = spawn workerSpawn()
  let res = ^fv
  let popped = popVerifier()
  echo "test2 main verifier count: ", popped.rewriteCount
  echo "spawn result: ", res
  echo "expected main-only: 1"

test2()
