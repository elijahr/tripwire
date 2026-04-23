## TRM module variant with ONLY the non-generic pattern.
import common

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  a + b + 1000

const nimfoot_auto_sentinel* = 42
