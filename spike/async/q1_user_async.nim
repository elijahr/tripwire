## Q1: Does a TRM fire on a user-defined async proc?
##
## `fetchAsync` is an async proc. We define a TRM matching `fetchAsync(url)`.
## Expectation unknown: the async transform rewrites the body into a Future
## state machine; it is unclear whether TRM pattern-matching sees the original
## call site or only the transformed state machine.
import std/asyncdispatch

proc fetchAsync*(url: string): Future[string] {.async.} =
  return "real result for " & url

var rewriteCount* = 0

template rewriteFetch*{fetchAsync(url)}(url: string): Future[string] =
  inc(rewriteCount)
  let f = newFuture[string]("fakeFetch")
  f.complete("mocked result")
  f

let r = waitFor fetchAsync("http://x")
echo "result=", r
echo "rewriteCount=", rewriteCount
