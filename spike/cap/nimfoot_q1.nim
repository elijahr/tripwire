## Non-recursive TRM: pattern matches `target`, rewrite expands to
## `rawTarget` + a counter bump. The rewrite output CANNOT match the
## pattern again — this is the nimfoot-style shape.
import common_q1

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  rawTarget(a, b)
