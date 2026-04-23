## Q1 TRM module: defines BOTH a low-layer (socket) and a high-layer (http) TRM.
## The high-layer rewrite body itself calls `socketSend`, which is what Q1
## probes: does the inner call also get rewritten?
import targets

var socketRewrites* {.global.} = 0
var httpRewrites* {.global.} = 0

template rewriteSocketSend*{socketSend(address, data)}(address, data: string) =
  inc(socketRewrites)
  # don't actually send

template rewriteHttpGet*{httpGet(url)}(url: string): string =
  inc(httpRewrites)
  socketSend(url, "GET intercepted\r\n")  # high-layer rewrite still calls socket
  "fake-response"
