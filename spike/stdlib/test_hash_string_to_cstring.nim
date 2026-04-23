## Probe: hash overload on string. Call site passes string literal.
## If both string and cstring overloads exist, call resolves to string.
## Does a cstring-declared TRM incorrectly try to match and fail?
## Does a string-declared TRM match the string overload?
import std/hashes

var rewriteCount {.global.} = 0

template rewriteHash{hash(x)}(x: string): Hash =
  inc(rewriteCount)
  Hash(0)

let h = hash("hello")
echo "h=", h, " rewriteCount=", rewriteCount
