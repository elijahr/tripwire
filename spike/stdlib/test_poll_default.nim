## Probe: poll() with no args (default=500) and TRM declaring `timeout: int`.
## Does the default fill happen before or after TRM matching?
import std/asyncdispatch

var rewriteCount {.global.} = 0

template rewritePoll{poll(timeout)}(timeout: int) =
  inc(rewriteCount)
  discard

poll()  ## no arg — relies on default=500
echo "rewriteCount=", rewriteCount
