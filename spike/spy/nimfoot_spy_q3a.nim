## Q3 variant A: inside-template let-binding to defeat re-matching.
## Idea: assign target to a local proc var; calling the var doesn't match
## the TRM pattern `target(a,b)`.
import common_spy

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  bind target
  let realFn = target
  realFn(a, b)
