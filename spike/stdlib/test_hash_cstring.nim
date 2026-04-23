## Probe: TRM against hash(x: cstring). Does a string-literal call site
## (which Nim implicitly converts to cstring via nkHiddenStdConv) match?
## Two variants: TRM with `x: cstring` (exact) and `x: string` (looser).
import std/hashes

var rewriteCount {.global.} = 0

template rewriteHash{hash(x)}(x: cstring): Hash =
  inc(rewriteCount)
  Hash(0)

let h = hash("hello".cstring)  ## explicit cstring at call site
echo "h=", h, " rewriteCount=", rewriteCount
