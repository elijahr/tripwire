## Literal shape from the spike's cautionary comment:
##   template foo*{targetGeneric(a, b)}[T](a, b: T): T = ...
## This is the pattern the comment at nimfoot_auto.nim:13-16 warns about.
import std/strutils

proc targetGeneric*[T](x, y: T): T = x + y

var rewriteCountGeneric* {.global.} = 0

template rewriteTargetGeneric*{targetGeneric(a, b)}[T](a, b: T): T =
  inc(rewriteCountGeneric)
  a + b + 1000

let r1 = targetGeneric(2, 3)
let r2 = targetGeneric[int](10, 20)
echo r1, " ", r2, " count=", rewriteCountGeneric
