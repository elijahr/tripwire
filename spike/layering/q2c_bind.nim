## Q2c: attempt to use `bind` in the rewrite body to reference socketSend
## directly, bypassing TRM rewriting.
import targets

var socketRewrites* {.global.} = 0
var httpRewrites* {.global.} = 0

template rewriteSocketSend*{socketSend(address, data)}(address, data: string) =
  inc(socketRewrites)

template rewriteHttpGet*{httpGet(url)}(url: string): string =
  bind socketSend
  inc(httpRewrites)
  socketSend(url, "GET intercepted\r\n")
  "fake-response"
