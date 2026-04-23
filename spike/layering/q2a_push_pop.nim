## Q2a: try {.push noRewrite: on.}/{.pop.} inside the high-layer rewrite body
## to suppress the low-layer TRM during the inner socketSend call.
import targets

var socketRewrites* {.global.} = 0
var httpRewrites* {.global.} = 0

template rewriteSocketSend*{socketSend(address, data)}(address, data: string) =
  inc(socketRewrites)

template rewriteHttpGet*{httpGet(url)}(url: string): string =
  inc(httpRewrites)
  {.push noRewrite: on.}
  socketSend(url, "GET intercepted\r\n")
  {.pop.}
  "fake-response"
