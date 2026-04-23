## Q2 variant B: wrap the original in an anonymous proc. The outer `target` is
## a normal call inside the lambda body — will term-rewriting still reach into it?
import common_spy

let origTarget* = proc(a, b: int): int = target(a, b)

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  origTarget(a, b)
