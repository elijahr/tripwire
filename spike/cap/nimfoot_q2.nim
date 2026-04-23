## Q2: defines BOTH TRMs in the same unit so they share `evalTemplateCounter`
## and `hloLoopDetector` state during sem of every consumer module.
##
## recursiveMul is the #9288 commutativity rule — rewriting `a * b` to `b * a`
## matches its own output, so depth explodes until the nesting cap fires.
##
## nimfootAdd is the non-recursive nimfoot shape — rewrite output uses
## `rawAddTarget` (a different name), so it can never re-match.
import common_q2

var recursiveFireCount* {.global.} = 0
var nimfootFireCount* {.global.} = 0

template recursiveMul*{`*`(a, b)}(a, b: int): int =
  inc(recursiveFireCount)
  `*`(b, a)

template nimfootAdd*{addTarget(a, b)}(a, b: int): int =
  inc(nimfootFireCount)
  rawAddTarget(a, b)
