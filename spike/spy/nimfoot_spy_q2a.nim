## Q2 variant A: capture target to a let before defining rewrite template.
## Does the captured pointer still re-match `target(a, b)` pattern?
import common_spy

let origTarget* = target

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  origTarget(a, b)
