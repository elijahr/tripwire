## Q2b: try pragma on the call itself: `socketSend(...) {.noRewrite.}`.
import targets

var socketRewrites* {.global.} = 0
var httpRewrites* {.global.} = 0

template rewriteSocketSend*{socketSend(address, data)}(address, data: string) =
  inc(socketRewrites)

template rewriteHttpGet*{httpGet(url)}(url: string): string =
  inc(httpRewrites)
  {.noRewrite.}:
    socketSend(url, "GET intercepted\r\n")
  "fake-response"
