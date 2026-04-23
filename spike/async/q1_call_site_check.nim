## Call-site verification: does the TRM fire synchronously at the call site,
## BEFORE the Future is constructed and run through the async dispatcher?
##
## Strategy: echo a marker inside the TRM body. If the TRM fires at the call
## site, the marker prints during expansion (before `waitFor` blocks). Also
## verify that the real proc body NEVER runs by echoing inside the real
## `fetchAsync` body — if the TRM fired at the call site, we should never
## see the "REAL BODY" marker.
import std/asyncdispatch

proc fetchAsync*(url: string): Future[string] {.async.} =
  echo "REAL BODY: url=", url
  return "real result for " & url

var rewriteCount* = 0

template rewriteFetch*{fetchAsync(url)}(url: string): Future[string] =
  echo "TRM body running; url=", url
  inc(rewriteCount)
  let f = newFuture[string]("fakeFetch")
  f.complete("mocked result")
  f

echo "-- before call --"
let fut = fetchAsync("http://x")  # does the TRM marker print here?
echo "-- after call, before waitFor --"
let r = waitFor fut
echo "-- after waitFor --"
echo "result=", r
echo "rewriteCount=", rewriteCount
