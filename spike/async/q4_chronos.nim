## Q4: Does a TRM fire on a user-defined async proc under `chronos` dispatcher?
##
## Mirrors Q1 but uses `import chronos` instead of `std/asyncdispatch`.
## chronos provides its own `async` macro and `Future[T]` type; the question
## is whether TRM pattern-matching still fires at the call site.
import chronos

proc fetchAsync*(url: string): Future[string] {.async.} =
  return "real result for " & url

var rewriteCount* = 0

proc makeMocked(val: string): Future[string] =
  result = newFuture[string]("fakeFetch")
  result.complete(val)

template rewriteFetch*{fetchAsync(url)}(url: string): Future[string] =
  inc(rewriteCount)
  makeMocked("mocked result")

let r = waitFor fetchAsync("http://x")
echo "result=", r
echo "rewriteCount=", rewriteCount
