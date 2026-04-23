## Q1 variant C: "pragma pushed at template scope" attempt.
## Does {.push noRewrite.} work inside the template body?
import common_spy

var rewriteCount* {.global.} = 0

template rewriteTarget*{target(a, b)}(a, b: int): int =
  inc(rewriteCount)
  {.push noRewrite.}
  let r = target(a, b)
  {.pop.}
  r
