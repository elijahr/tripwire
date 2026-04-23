## Q1 variant B (observable): pragma-block + an observable offset.
## If noRewrite is respected, each call fires exactly once so the result
## will be exactly one offset on top of the real sum.
import common_spy

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  {.noRewrite.}:
    target(a, b) + 1000
