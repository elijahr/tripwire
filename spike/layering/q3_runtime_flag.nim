## Q3: the "graceful no-op" pattern — runtime flag controls whether the
## high-layer rewrite fires or falls through. The challenge: once the TRM has
## matched, the original proc call site has been replaced by the template
## body. There is no "cancel match and run original" operator. We must emulate
## fall-through by calling a non-intercepted variant inside the rewrite.

import targets

var httpInterceptEnabled* {.global.} = true
var httpRewrites* {.global.} = 0

## The rewrite body receives `url`. To "fall through" we need to invoke the
## real httpGet, but a naive re-call would re-match the pattern (infinite
## recursion). Use `{.noRewrite.}:` to escape the loop and reach the original.
template rewriteHttpGet*{httpGet(url)}(url: string): string =
  if httpInterceptEnabled:
    inc(httpRewrites)
    "fake-response"
  else:
    {.noRewrite.}:
      httpGet(url)
