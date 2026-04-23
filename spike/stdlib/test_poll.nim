## Target 8: std/asyncdispatch.poll(timeout: int) — void, with default.
import std/asyncdispatch

var rewriteCount {.global.} = 0

template rewritePoll{poll(timeout)}(timeout: int) =
  inc(rewriteCount)
  discard

poll(0)
echo "rewriteCount=", rewriteCount
