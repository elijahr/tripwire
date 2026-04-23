## Q3b: what happens without noRewrite? The rewrite body re-calls httpGet,
## which should re-match and recurse. Expected: infinite recursion (stack
## overflow at runtime) or compiler error.
import targets

var httpInterceptEnabled* {.global.} = true
var httpRewrites* {.global.} = 0

template rewriteHttpGet*{httpGet(url)}(url: string): string =
  if httpInterceptEnabled:
    inc(httpRewrites)
    "fake-response"
  else:
    httpGet(url)  # no noRewrite — will this recurse?
