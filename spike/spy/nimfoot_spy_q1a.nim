## Q1 variant A: {.noRewrite.} as a pragma on the call expression.
## Syntax: `target(a, b) {.noRewrite.}`
import common_spy

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  target(a, b) {.noRewrite.}
