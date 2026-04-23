## Q1 variant B: {.noRewrite.} as a pragma block.
## Syntax: {.noRewrite.}: target(a, b)
import common_spy

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  {.noRewrite.}:
    target(a, b)
