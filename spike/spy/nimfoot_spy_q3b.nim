## Q3 variant B: the literal formulation from the task — let with {.noRewrite.} pragma.
import common_spy

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  bind target
  let realFn {.noRewrite.} = target
  realFn(a, b)
